#include "pch.h"
#include "RCTPdfControl.h"
#if __has_include("RCTPdfControl.g.cpp")
#include "RCTPdfControl.g.cpp"
#endif

using namespace winrt;
using namespace Windows::UI::Xaml;
using namespace Microsoft::ReactNative;
using namespace Windows::Data::Json;
using namespace Windows::Data::Pdf;
using namespace Windows::Foundation;
using namespace Windows::Storage;
using namespace Windows::Storage::Streams;
using namespace Windows::Storage::Pickers;
using namespace Windows::UI;
using namespace Windows::UI::Core;
using namespace Windows::UI::Popups;
using namespace Windows::UI::Xaml;
using namespace Windows::UI::Xaml::Controls;
using namespace Windows::UI::Xaml::Input;
using namespace Windows::UI::Xaml::Media;
using namespace Windows::UI::Xaml::Media::Imaging;
using namespace Windows::UI::Xaml::Documents;
using namespace Windows::UI::Xaml::Shapes;

namespace winrt::RCTPdf::implementation
{
  PDFPageInfo::PDFPageInfo(winrt::Windows::UI::Xaml::Controls::Image image, winrt::Windows::Data::Pdf::PdfPage page, double imageScale, double renderScale) :
    image(image), page(page), imageScale(imageScale), renderScale(renderScale), scaledTopOffset(0), scaledLeftOffset(0) {
    auto dims = page.Size();
    height = (unsigned)dims.Height;
    width = (unsigned)dims.Width;
    scaledHeight = (unsigned)(height * imageScale);
    scaledWidth = (unsigned)(width * imageScale);
  }
  PDFPageInfo::PDFPageInfo(const PDFPageInfo& rhs) :
    height(rhs.height), width(rhs.width), scaledHeight(rhs.scaledHeight), scaledWidth(rhs.scaledWidth),
    scaledTopOffset(rhs.scaledTopOffset), scaledLeftOffset(rhs.scaledTopOffset), imageScale(rhs.imageScale),
    renderScale((double)rhs.renderScale), image(rhs.image), page(rhs.page)
  { }
  PDFPageInfo::PDFPageInfo(PDFPageInfo&& rhs) :
    height(rhs.height), width(rhs.width), scaledHeight(rhs.scaledHeight), scaledWidth(rhs.scaledWidth),
    scaledTopOffset(rhs.scaledTopOffset), scaledLeftOffset(rhs.scaledTopOffset), imageScale(rhs.imageScale),
    renderScale((double)rhs.renderScale), image(std::move(rhs.image)), page(std::move(rhs.page))
  { }
  unsigned PDFPageInfo::pageVisiblePixels(bool horizontal, double viewportStart, double viewportEnd) const {
    if (viewportEnd < viewportStart)
      std::swap(viewportStart, viewportEnd);
    auto pageStart = horizontal ? scaledLeftOffset : scaledTopOffset;
    auto pageSize = PDFPageInfo::pageSize(horizontal);
    auto pageEnd = pageStart + pageSize;
    auto uViewportStart = (unsigned)viewportStart;
    auto uViewportEnd = (unsigned)viewportEnd;
    if (pageStart >= uViewportStart && pageStart <= uViewportEnd) { // we see the top edge
      return (std::min)(pageEnd, uViewportEnd) - pageStart;
    }
    if (pageEnd >= uViewportStart && pageEnd <= uViewportEnd) { // we see the bottom edge
      return pageEnd - (std::max)(pageStart, uViewportStart);
    }
    if (pageStart <= uViewportStart && pageEnd >= uViewportEnd) {// we see the entire page
      return uViewportEnd - uViewportStart;
    }
    return 0;
  }
  unsigned PDFPageInfo::pageSize(bool horizontal) const {
    return horizontal ? scaledWidth : scaledHeight;
  }
  bool PDFPageInfo::needsRender() const {
    double currentRenderScale = renderScale;
    return currentRenderScale < imageScale || currentRenderScale > imageScale * m_downscaleTreshold;
  }
  winrt::Windows::Foundation::IAsyncAction PDFPageInfo::render() {
    return render(imageScale);
  }
  winrt::Windows::Foundation::IAsyncAction PDFPageInfo::render(double useScale) {
    double currentRenderScale;
    while (true) {
      currentRenderScale = renderScale;
      if (!(currentRenderScale < imageScale || currentRenderScale > imageScale * m_downscaleTreshold))
        co_return;
      if (renderScale.compare_exchange_weak(currentRenderScale, useScale))
        break;
      if (renderScale > useScale)
        co_return;
    }
    PdfPageRenderOptions renderOptions;
    auto dims = page.Size();
    renderOptions.DestinationHeight(static_cast<uint32_t>(dims.Height * useScale));
    renderOptions.DestinationWidth(static_cast<uint32_t>(dims.Width * useScale));
    InMemoryRandomAccessStream stream;
    co_await page.RenderToStreamAsync(stream, renderOptions);
    BitmapImage bitmap;
    co_await bitmap.SetSourceAsync(stream);
    if (renderScale == useScale && image != nullptr && bitmap != nullptr)
      image.Source(bitmap);
  }
  
  RCTPdfControl::RCTPdfControl(IReactContext const& reactContext) : m_reactContext(reactContext) {
    InitializeComponent();
  }

  winrt::Windows::Foundation::Collections::IMapView<winrt::hstring, winrt::Microsoft::ReactNative::ViewManagerPropertyType> RCTPdfControl::NativeProps() noexcept {
    auto nativeProps = winrt::single_threaded_map<hstring, ViewManagerPropertyType>();
    nativeProps.Insert(L"path", ViewManagerPropertyType::String);
    nativeProps.Insert(L"page", ViewManagerPropertyType::Number);
    nativeProps.Insert(L"scale", ViewManagerPropertyType::Number);
    nativeProps.Insert(L"minScale", ViewManagerPropertyType::Number);
    nativeProps.Insert(L"maxScale", ViewManagerPropertyType::Number);
    nativeProps.Insert(L"horizontal", ViewManagerPropertyType::Boolean);
    nativeProps.Insert(L"fitWidth", ViewManagerPropertyType::Boolean);
    nativeProps.Insert(L"fitPolicy", ViewManagerPropertyType::Number);
    nativeProps.Insert(L"spacing", ViewManagerPropertyType::Number);
    nativeProps.Insert(L"password", ViewManagerPropertyType::String);
    nativeProps.Insert(L"background", ViewManagerPropertyType::Color);
    nativeProps.Insert(L"enablePaging", ViewManagerPropertyType::Boolean);
    nativeProps.Insert(L"enableRTL", ViewManagerPropertyType::Boolean);
    nativeProps.Insert(L"singlePage", ViewManagerPropertyType::Boolean);
    nativeProps.Insert(L"hotspots", ViewManagerPropertyType::String);
    nativeProps.Insert(L"notes", ViewManagerPropertyType::String);
    nativeProps.Insert(L"textNotes", ViewManagerPropertyType::String);

    return nativeProps.GetView();
  }

  void RCTPdfControl::UpdateProperties(winrt::Microsoft::ReactNative::IJSValueReader const& propertyMapReader) noexcept {    
    const JSValueObject& propertyMap = JSValue::ReadObjectFrom(propertyMapReader);
    std::optional<std::string> pdfURI;
    std::optional<std::string> pdfPassword;
    std::optional<int> setPage;
    std::optional<double> minScale, maxScale, scale;
    std::optional<bool> horizontal;
    std::optional<bool> fitWidth;
    std::optional<int> fitPolicy;
    std::optional<int> spacing;
    std::optional<bool> reverse;
    std::optional<bool> singlePage;
    std::optional<bool> enablePaging;
    for (auto const& pair : propertyMap) {
      auto const& propertyName = pair.first;
      auto const& propertyValue = pair.second;
      if (propertyName == "path") {
        pdfURI = propertyValue != nullptr ? propertyValue.AsString() : "";
      }
      else if (propertyName == "password") {
        pdfPassword = propertyValue != nullptr ? propertyValue.AsString() : "";
      }
      else if (propertyName == "page" && propertyValue != nullptr) {
        setPage = propertyValue.AsInt32() - 1;
      }
      else if (propertyName == "scale" && propertyValue != nullptr) {
        scale = propertyValue.AsDouble();
      }
      else if (propertyName == "minScale" && propertyValue != nullptr) {
        minScale = propertyValue.AsDouble();
      }
      else if (propertyName == "maxScale" && propertyValue != nullptr) {
        maxScale = propertyValue.AsDouble();
      }
      else if (propertyName == "horizontal" && propertyValue != nullptr) {
        horizontal = propertyValue.AsBoolean();
      }
      else if (propertyName == "enablePaging" && propertyValue != nullptr) {
        enablePaging = propertyValue.AsBoolean();
      }
      else if (propertyName == "fitWidth" && propertyValue != nullptr) {
        fitWidth = propertyValue.AsBoolean();
      }
      else if (propertyName == "fitPolicy" && propertyValue != nullptr) {
        fitPolicy = propertyValue.AsInt32();
      }
      else if (propertyName == "spacing" && propertyValue != nullptr) {
        maxScale = propertyValue.AsInt32();
      }
      else if (propertyName == "enableRTL" && propertyValue != nullptr) {
        reverse = propertyValue.AsBoolean();
      }
      else if (propertyName == "singlePage" && propertyValue != nullptr) {
        singlePage = propertyValue.AsBoolean();
      }
      else if (propertyName == "hotspots" && propertyValue != nullptr) {
        try {
          auto jsonArray = winrt::Windows::Data::Json::JsonArray::Parse(winrt::to_hstring(propertyValue.AsString()));
          m_hotspots.clear();
          for (auto item : jsonArray) {
            auto obj = item.GetObject();
            HotspotInfo h;
            // xPos/yPos can be JSON strings (e.g. "27.82") or numbers, and are percentages (0-100)
            auto parsePercent = [&](const wchar_t* key) -> double {
              auto val = obj.GetNamedValue(key, winrt::Windows::Data::Json::JsonValue::CreateNullValue());
              double raw = 50.0;
              if (val.ValueType() == winrt::Windows::Data::Json::JsonValueType::Number) {
                raw = val.GetNumber();
              } else if (val.ValueType() == winrt::Windows::Data::Json::JsonValueType::String) {
                try { raw = std::stod(winrt::to_string(val.GetString())); } catch (...) {}
              }
              return raw / 100.0;
            };
            h.xPos = parsePercent(L"xPos");
            h.yPos = parsePercent(L"yPos");
            h.uid  = winrt::to_string(obj.GetNamedString(L"uid",  L""));
            h.type = winrt::to_string(obj.GetNamedString(L"type", L""));
            m_hotspots.push_back(h);
          }
        } catch (...) {
          m_hotspots.clear();
        }
        UpdateHotspots();
      }
      else if (propertyName == "notes" && propertyValue != nullptr) {
        try {
          auto jsonArray = winrt::Windows::Data::Json::JsonArray::Parse(winrt::to_hstring(propertyValue.AsString()));
          m_notes.clear();
          for (auto item : jsonArray) {
            auto obj = item.GetObject();
            NoteInfo n;
            auto parsePercent = [&](const wchar_t* key) -> double {
              auto val = obj.GetNamedValue(key, winrt::Windows::Data::Json::JsonValue::CreateNullValue());
              double raw = 50.0;
              if (val.ValueType() == winrt::Windows::Data::Json::JsonValueType::Number) {
                raw = val.GetNumber();
              } else if (val.ValueType() == winrt::Windows::Data::Json::JsonValueType::String) {
                try { raw = std::stod(winrt::to_string(val.GetString())); } catch (...) {}
              }
              return raw / 100.0;
            };
            n.xPos  = parsePercent(L"xPos");
            n.yPos  = parsePercent(L"yPos");
            n.uid   = winrt::to_string(obj.GetNamedString(L"uid",   L""));
            n.color = winrt::to_string(obj.GetNamedString(L"color", L""));
            m_notes.push_back(n);
          }
        } catch (...) {
          m_notes.clear();
        }
        UpdateNotes();
      }
      else if (propertyName == "textNotes" && propertyValue != nullptr) {
        try {
          auto jsonArray = winrt::Windows::Data::Json::JsonArray::Parse(winrt::to_hstring(propertyValue.AsString()));
          m_textNotes.clear();
          for (auto item : jsonArray) {
            auto obj = item.GetObject();
            TextNoteInfo t;
            auto parsePercent = [&](const wchar_t* key) -> double {
              auto val = obj.GetNamedValue(key, winrt::Windows::Data::Json::JsonValue::CreateNullValue());
              double raw = 0.0;
              if (val.ValueType() == winrt::Windows::Data::Json::JsonValueType::Number) {
                raw = val.GetNumber();
              } else if (val.ValueType() == winrt::Windows::Data::Json::JsonValueType::String) {
                try { raw = std::stod(winrt::to_string(val.GetString())); } catch (...) {}
              }
              return raw / 100.0;
            };
            t.uid    = winrt::to_string(obj.GetNamedString(L"uid", L""));
            t.xPos   = parsePercent(L"xPos");
            t.yPos   = parsePercent(L"yPos");
            t.width  = parsePercent(L"width");
            t.height = parsePercent(L"height");
            t.backgroundColor = winrt::to_string(obj.GetNamedString(L"backgroundColor", L"#FFFF00"));
            auto parseDouble = [&](const wchar_t* key, double def) -> double {
              auto v = obj.GetNamedValue(key, winrt::Windows::Data::Json::JsonValue::CreateNullValue());
              if (v.ValueType() == winrt::Windows::Data::Json::JsonValueType::Number) return v.GetNumber();
              if (v.ValueType() == winrt::Windows::Data::Json::JsonValueType::String) {
                try { return std::stod(winrt::to_string(v.GetString())); } catch (...) {}
              }
              return def;
            };
            t.backgroundOpacity = parseDouble(L"backgroundOpacity", 1.0);
            t.borderColor       = winrt::to_string(obj.GetNamedString(L"borderColor", L"transparent"));
            t.borderOpacity     = parseDouble(L"borderOpacity", 1.0);
            t.borderSize        = parseDouble(L"borderSize", 0.0);
            t.lines.clear();
            auto linesVal = obj.GetNamedValue(L"lines", winrt::Windows::Data::Json::JsonValue::CreateNullValue());
            if (linesVal.ValueType() == winrt::Windows::Data::Json::JsonValueType::Array) {
              for (auto lineItem : linesVal.GetArray()) {
                TextNoteLine tl;
                if (lineItem.ValueType() == winrt::Windows::Data::Json::JsonValueType::Object) {
                  auto lineObj = lineItem.GetObject();
                  tl.text      = winrt::to_string(lineObj.GetNamedString(L"text",      L""));
                  tl.fontColor = winrt::to_string(lineObj.GetNamedString(L"fontColor", L"#000000"));
                  auto parseLineNum = [&](const wchar_t* key, double def) -> double {
                    auto v = lineObj.GetNamedValue(key, winrt::Windows::Data::Json::JsonValue::CreateNullValue());
                    if (v.ValueType() == winrt::Windows::Data::Json::JsonValueType::Number) return v.GetNumber();
                    if (v.ValueType() == winrt::Windows::Data::Json::JsonValueType::String) {
                      try { return std::stod(winrt::to_string(v.GetString())); } catch (...) {}
                    }
                    return def;
                  };
                  tl.fontSize    = parseLineNum(L"fontSize",    14.0);
                  tl.fontOpacity = parseLineNum(L"fontOpacity",  1.0);
                }
                t.lines.push_back(tl);
              }
            }
            m_textNotes.push_back(t);
          }
        } catch (...) {
          m_textNotes.clear();
        }
        UpdateTextNotes();
      }
      else if (propertyName == "backgroundColor" && propertyValue != nullptr) {
        auto color = propertyValue.AsInt32();
        winrt::Windows::UI::Color brushColor;
        brushColor.A = (color >> 24) & 0xff;
        brushColor.R = (color >> 16) & 0xff;
        brushColor.G = (color >> 8) & 0xff;
        brushColor.B = color & 0xff;
        PagesContainer().Background(SolidColorBrush(brushColor));
      }
    }

    // If we are loading a new PDF:
    //std::shared_lock lock(m_rwlock);
    if (pdfURI && *pdfURI != m_pdfURI ||
        pdfPassword && *pdfPassword != m_pdfPassword ||
        (reverse && *reverse != m_reverse) ||
        (enablePaging && *enablePaging != m_enablePaging) ||
        (singlePage && (m_pages.empty() || *singlePage && m_pages.size() != 1 || !*singlePage && m_pages.size() == 1)) ) {
      //lock.unlock();
      std::unique_lock write_lock(m_rwlock);
      m_pdfURI = pdfURI.value_or("");
      m_pdfPassword = pdfPassword.value_or("");
      m_currentPage = setPage.value_or(0);
      m_scale = scale.value_or(m_defualtZoom);
      m_minScale = minScale.value_or(m_defaultMinZoom);
      m_maxScale = maxScale.value_or(m_defaultMaxZoom);
      m_horizontal = horizontal.value_or(true);
      m_enablePaging = enablePaging.value_or(false);

      int useFitPolicy = 2;
      if (fitWidth)
        useFitPolicy = 0;
      if (fitPolicy)
        useFitPolicy = *fitPolicy;
      m_margins = spacing.value_or(m_defaultMargins);
      m_reverse = reverse.value_or(false);
      //LoadPDF(std::move(write_lock), useFitPolicy, singlePage.value_or(false));
      LoadPDF(/*std::move(write_lock), */ useFitPolicy, singlePage.value_or(false));
    } else {
      // If we are updating the pdf:
      m_minScale = minScale.value_or(m_minScale);
      m_maxScale = maxScale.value_or(m_maxScale);
      bool needScroll = false;
      if (horizontal && *horizontal != m_horizontal) {
        SetOrientation(*horizontal);
        needScroll = true;
      }
      if (setPage) {
        m_currentPage = *setPage;
        needScroll = true;
      }
      if ((scale && *scale != m_scale) || (spacing && *spacing != m_margins)) {
        Rescale(scale.value_or(m_scale), spacing.value_or(m_margins), true);
      }
      if (needScroll) {
        GoToPage(m_currentPage);
      }
    }
  }

  winrt::Microsoft::ReactNative::ConstantProviderDelegate RCTPdfControl::ExportedCustomBubblingEventTypeConstants() noexcept {
    return [](IJSValueWriter const& constantWriter) {
      WriteCustomDirectEventTypeConstant(constantWriter, "Change");
    };
  }
  winrt::Microsoft::ReactNative::ConstantProviderDelegate RCTPdfControl::ExportedCustomDirectEventTypeConstants() noexcept {
    return [](winrt::Microsoft::ReactNative::IJSValueWriter const& constantWriter) {
      WriteCustomDirectEventTypeConstant(constantWriter, "HotspotPress");
    };
  }
  
  winrt::Windows::Foundation::Collections::IVectorView<winrt::hstring> RCTPdfControl::Commands() noexcept {
    auto commands = winrt::single_threaded_vector<hstring>();
    commands.Append(L"setPage");
    return commands.GetView();
  }

  void RCTPdfControl::DispatchCommand(winrt::hstring const& commandId, winrt::Microsoft::ReactNative::IJSValueReader const& commandArgsReader) noexcept {
    auto commandArgs = JSValue::ReadArrayFrom(commandArgsReader);
    if (commandId == L"setPage" && commandArgs.size() > 0) {
      std::shared_lock lock(m_rwlock);
      auto page = commandArgs[0].AsInt32() - 1;
      GoToPage(page);
    }
  }

  void RCTPdfControl::PagesContainer_PointerWheelChanged(winrt::Windows::Foundation::IInspectable const&, winrt::Windows::UI::Xaml::Input::PointerRoutedEventArgs const& e) {
    /*winrt::Windows::System::VirtualKeyModifiers modifiers = e.KeyModifiers();
    if ((modifiers & winrt::Windows::System::VirtualKeyModifiers::Control) != winrt::Windows::System::VirtualKeyModifiers::Control)
      return;
    double delta = (e.GetCurrentPoint(*this).Properties().MouseWheelDelta() / WHEEL_DELTA);*/
    OutputDebugString(L"ok ja bebes");
    /*std::shared_lock lock(m_rwlock);
    auto newScale = (std::max)((std::min)(m_scale * pow(m_zoomMultiplier, delta), m_maxScale), m_minScale);
    Rescale(newScale, m_margins, true);
    SignalScaleChanged(m_scale, PagesContainer().HorizontalOffset(), PagesContainer().VerticalOffset());*/
    e.Handled(true);
  }

  void RCTPdfControl::PagesContainer_PointerPressed(winrt::Windows::Foundation::IInspectable const&, winrt::Windows::UI::Xaml::Input::PointerRoutedEventArgs const& e) {
      offset_X = PagesContainer().HorizontalOffset();
      offset_Y = PagesContainer().VerticalOffset();
      drag_X = e.GetCurrentPoint(*this).Position().X;
      drag_Y = e.GetCurrentPoint(*this).Position().Y;
      e.Handled(true);
  }

  void RCTPdfControl::PagesContainer_PointerReleased(winrt::Windows::Foundation::IInspectable const&, winrt::Windows::UI::Xaml::Input::PointerRoutedEventArgs const& e) {
      drag_X = 0;
      drag_Y = 0;
      e.Handled(true);
  }

  void RCTPdfControl::PagesContainer_PointerMoved(winrt::Windows::Foundation::IInspectable const&, winrt::Windows::UI::Xaml::Input::PointerRoutedEventArgs const& e) {
      if (e.GetCurrentPoint(*this).IsInContact()) {
          if (drag_X != 0 && drag_Y != 0) {
              double targetHorizontalOffset = offset_X - (e.GetCurrentPoint(*this).Position().X - drag_X);
              double targetVerticalOffset = offset_Y - (e.GetCurrentPoint(*this).Position().Y - drag_Y);

              ChangeScroll(targetHorizontalOffset, targetVerticalOffset);
          }
      }
      else {
          drag_X = 0;
          drag_Y = 0;
      }
      e.Handled(true);
  }



  void RCTPdfControl::Pages_SizeChanged(winrt::Windows::Foundation::IInspectable const&, winrt::Windows::UI::Xaml::SizeChangedEventArgs const&) {
    if (m_targetHorizontalOffset || m_targetVerticalOffset) {
      auto container = PagesContainer();
      PagesContainer().ChangeView(m_targetHorizontalOffset.value_or(container.HorizontalOffset()),
        m_targetVerticalOffset.value_or(container.VerticalOffset()),
        nullptr,
        true);
      m_targetHorizontalOffset.reset();
      m_targetVerticalOffset.reset();
    }
    UpdateHotspots();
    UpdateNotes();
    UpdateTextNotes();
  }

  winrt::fire_and_forget RCTPdfControl::PagesContainer_ViewChanged(winrt::Windows::Foundation::IInspectable const&, winrt::Windows::UI::Xaml::Controls::ScrollViewerViewChangedEventArgs const& args)
  {
    auto lifetime = get_strong();
    auto container = PagesContainer();
    auto currentHorizontalOffset = 0;
    auto width = container.Width();
    auto height = container.Width();
    auto currentVerticalOffset = 0;
    double offsetStart = m_horizontal ? currentHorizontalOffset : currentVerticalOffset;
    auto viewWidth = container.ViewportWidth();
    auto viewHeight = container.ViewportHeight();
    double viewSize = m_horizontal ? viewWidth : viewHeight;
    double offsetEnd = offsetStart + viewSize;
    //SignalScaleChanged(10, currentHorizontalOffset, currentVerticalOffset);
    std::shared_lock lock(m_rwlock, std::defer_lock);

    SignalScaleChanged(m_scale, PagesContainer().HorizontalOffset(), PagesContainer().VerticalOffset());

    if (args.IsIntermediate() || !lock.try_lock() || viewSize == 0 || m_pages.empty())
      return;
    // Go through pages until we reach a visible page
    int page = 0;
    double visiblePagePixels = 0;
    for (; page < (int)m_pages.size(); ++page) {
      visiblePagePixels = m_pages[page].pageVisiblePixels(m_horizontal, offsetStart, offsetEnd);
      if (visiblePagePixels > 0)
        break;
    }
    if (page == (int)m_pages.size()) {
      --page;
    }
    else {
      double pagePixels = m_pages[page].pageSize(m_horizontal);
      // #"page" is the first visible page. Check how much of the view port this page covers...
      double viewCoveredByPage = visiblePagePixels / viewSize;
      // ...and how much of the page is visible:
      double pageVisiblePart = visiblePagePixels / pagePixels;
      // If:
      //  - less than 50% of the screen is covered by the page
      //  - less than 50% of the page is visible (important if more than one page fits the screen)
      //  - there is a next page
      // move the indicator to that page:
      if (viewCoveredByPage < 0.5 && pageVisiblePart < 0.5 && page + 1 < (int)m_pages.size()) {
        ++page;
      }
    }
    // Render all visible pages - first the current one, then the next visible ones and one
    // more, then the one before that might be partly visible, then one more before

    
    co_await RenderVisiblePages(page);
    if (page != m_currentPage) {
      m_currentPage = page;
      SignalPageChange(m_currentPage + 1, m_pages.size());
    }
  }

  void RCTPdfControl::PagesContainer_Tapped(winrt::Windows::Foundation::IInspectable const&, winrt::Windows::UI::Xaml::Input::TappedRoutedEventArgs const& args) {

      OutputDebugString(L"ok ja bebes tap");

    auto position = args.GetPosition(*this);
    std::shared_lock lock(m_rwlock);
    int scaledDoubleMargin = (int)(m_scale * m_margins * 2);
    int page = 0;
    int xPosition = (int)(position.X + PagesContainer().HorizontalOffset());
    int yPosition = (int)(position.Y + PagesContainer().VerticalOffset());
    for (; page < (int)m_pages.size(); ++page) {
      if (m_horizontal) {
        if (xPosition >= (int)m_pages[page].scaledLeftOffset &&
            xPosition <= (int)(m_pages[page].scaledLeftOffset + m_pages[page].scaledWidth + scaledDoubleMargin))
          break;   
      } else {
        if (yPosition >= (int)m_pages[page].scaledTopOffset &&
            yPosition <= (int)(m_pages[page].scaledTopOffset + m_pages[page].scaledHeight + scaledDoubleMargin))
          break;
      }
    }
    if (page == (int)m_pages.size()) {
      page = m_currentPage;
    }
    if (!m_activeTextNoteUid.empty()) {
      m_activeTextNoteUid.clear();
      for (auto& [uid, setter] : m_textNoteEditModeSetters)  setter(false);
      for (auto& [uid, setter] : m_textNoteTextEditSetters)  setter(false);
    }
    SignalPageTapped(page, (int)position.X, (int)position.Y);
    PagesContainer().Focus(FocusState::Pointer);
    args.Handled(true);
  }


  void RCTPdfControl::PagesContainer_DoubleTapped(winrt::Windows::Foundation::IInspectable const&, winrt::Windows::UI::Xaml::Input::DoubleTappedRoutedEventArgs const& args)
  {
    std::shared_lock lock(m_rwlock);
    double newScale = (std::min)(m_scale * m_zoomMultiplier, m_maxScale);
    Rescale(newScale, m_margins, true);
    PagesContainer().Focus(FocusState::Pointer);
    args.Handled(true);
  }

  void RCTPdfControl::ChangeScroll(double targetHorizontalOffset, double targetVerticalOffset) {
      
    auto container = PagesContainer();
    auto maxHorizontalOffset = container.ScrollableWidth();
    auto maxVerticalOffset = container.ScrollableHeight();

    auto viewWidth = container.ViewportWidth();
    auto viewHeight = container.ViewportHeight();
    
    if (targetHorizontalOffset <= maxHorizontalOffset + viewWidth &&
      targetVerticalOffset <= maxVerticalOffset + viewHeight) {
        
      PagesContainer().ChangeView((std::min)(targetHorizontalOffset, maxHorizontalOffset),
        (std::min)(targetVerticalOffset, maxVerticalOffset),
        nullptr, true);
      
    }
    else {
      m_targetHorizontalOffset = targetHorizontalOffset;
      m_targetVerticalOffset = targetVerticalOffset;
    }

    //SignalScaleChanged(m_scale, PagesContainer().HorizontalOffset(), PagesContainer().VerticalOffset());
  }

  void RCTPdfControl::UpdatePagesInfoMarginOrScale() {
    unsigned scaledMargin = (unsigned)(m_scale * m_margins);
    for (auto& page : m_pages) {
      page.imageScale = m_scale;
      page.scaledWidth = (unsigned)(page.width * m_scale);
      page.scaledHeight = (unsigned)(page.height * m_scale);
      page.image.Margin(ThicknessHelper::FromUniformLength(scaledMargin));
      page.image.Width(page.scaledWidth);
      page.image.Height(page.scaledHeight);
    }
    unsigned totalTopOffset = 0;
    unsigned totalLeftOffset = 0;
    unsigned doubleScaledMargin = scaledMargin * 2;
    if (m_reverse) {
      for (int page = m_pages.size() - 1; page >= 0; --page) {
        m_pages[page].scaledTopOffset = totalTopOffset;
        totalTopOffset += m_pages[page].scaledHeight + doubleScaledMargin;
        m_pages[page].scaledLeftOffset = totalLeftOffset;
        totalLeftOffset += m_pages[page].scaledWidth + doubleScaledMargin;
      }
    }
    else {
      for (int page = 0; page < (int)m_pages.size(); ++page) {
        m_pages[page].scaledTopOffset = totalTopOffset;
        totalTopOffset += m_pages[page].scaledHeight + doubleScaledMargin;
        m_pages[page].scaledLeftOffset = totalLeftOffset;
        totalLeftOffset += m_pages[page].scaledWidth + doubleScaledMargin;
      }
    }
  }

  void RCTPdfControl::GoToPage(int page) {
    if (page < 0 || page >= (int)m_pages.size()) {
      return;
    }
    if (m_enablePaging) {
      [&](int page) -> winrt::fire_and_forget {
        auto lifetime = get_strong();
        co_await m_pages[page].render();
      }(page);
      Pages().Items().ReplaceAll({ &m_pages[page].image, &m_pages[page].image + 1 });
    } else {
      auto neededOffset = m_horizontal ? m_pages[page].scaledLeftOffset : m_pages[page].scaledTopOffset;

      
      double horizontalOffset = m_horizontal ? neededOffset : PagesContainer().HorizontalOffset();
      double verticalOffset = m_horizontal ? PagesContainer().VerticalOffset() : neededOffset;

      ChangeScroll(horizontalOffset, verticalOffset);
    }
    SignalPageChange(page + 1, m_pages.size());
  }

  winrt::fire_and_forget RCTPdfControl::LoadPDF(/*std::unique_lock<std::shared_mutex> lock, */ int fitPolicy, bool singlePage) {
    auto lifetime = get_strong();
    auto pdfURI = m_pdfURI;
    auto uri = Uri(winrt::to_hstring(pdfURI));
    auto scheme = uri.SchemeName();
    if (scheme == L"file") {
      // backslashes only on Windows
      std::replace(begin(pdfURI), end(pdfURI), '/', '\\');
    }
    PdfDocument document = nullptr;
    try {
      auto file = scheme == L"file"
                  ? co_await StorageFile::GetFileFromPathAsync(winrt::to_hstring(pdfURI))
                  : co_await StorageFile::GetFileFromApplicationUriAsync(uri);
      document = co_await PdfDocument::LoadFromFileAsync(file, winrt::to_hstring(m_pdfPassword));
    }
    catch (winrt::hresult_error const& ex) {
      switch (ex.to_abi()) {
      case __HRESULT_FROM_WIN32(ERROR_WRONG_PASSWORD):
        SignalError("Password required or incorrect password.");
        co_return;
      case E_FAIL:
        SignalError("Document is not a valid PDF.");
        co_return;
      default:
        SignalError(winrt::to_string(ex.message()));
        co_return;
      }
    }
    if (!document) {
      SignalError("Could not load PDF.");
      co_return;
    }
    auto items = Pages().Items();
    items.Clear();
    m_pages.clear();
    SetOrientation(m_horizontal);

    auto viewWidth = PagesContainer().ViewportWidth();
    auto viewHeight = PagesContainer().ViewportHeight();
    if (viewWidth == 0) {
        InitializeComponent();
        LoadPDF(fitPolicy, singlePage);
    }
    else {
        if (document.PageCount() == 0) {
            if (fitPolicy != -1)
                m_scale = 1;
        }
        else {
            auto firstPageSize = document.GetPage(0).Size();
            switch (fitPolicy) {
            case 0:
                m_scale = viewWidth / (firstPageSize.Width + 2 * (double)m_margins);
                break;
            case 1:
                m_scale = viewHeight / (firstPageSize.Height + 2 * (double)m_margins);
                break;
            case 2:
                m_scale = (std::min)(viewWidth / (firstPageSize.Width + 2 * (double)m_margins), viewHeight / (firstPageSize.Height + 2 * (double)m_margins));
                break;
            default:
                m_scale = (std::min)(viewWidth / (firstPageSize.Width + 2 * (double)m_margins), viewHeight / (firstPageSize.Height + 2 * (double)m_margins));
                break;
            }
        }
        //}


        unsigned pagesCount = document.PageCount();
        if (singlePage && pagesCount > 0)
            pagesCount = 1;
        for (unsigned pageIdx = 0; pageIdx < pagesCount; ++pageIdx) {
            auto page = document.GetPage(pageIdx);
            auto dims = page.Size();
            Image pageImage;
            pageImage.HorizontalAlignment(HorizontalAlignment::Center);
            pageImage.AllowFocusOnInteraction(true);
            Automation::AutomationProperties::SetName(pageImage, winrt::to_hstring("PDF Page " + std::to_string(pageIdx + 1)));
            m_pages.emplace_back(pageImage, page, m_scale, 0);
        }
        if (m_enablePaging) {
            items.Append(m_pages[m_currentPage].image);
        }
        else {
            if (m_reverse) {
                for (int page = m_pages.size() - 1; page >= 0; --page)
                    items.Append(m_pages[page].image);
            }
            else {
                for (int page = 0; page < (int)m_pages.size(); ++page)
                    items.Append(m_pages[page].image);
            }
        }
        UpdatePagesInfoMarginOrScale();
        //lock.unlock();
        std::shared_lock shared_lock(m_rwlock);
        if (m_currentPage < 0)
            m_currentPage = 0;
        if (m_currentPage < (int)m_pages.size()) {
            co_await m_pages[m_currentPage].render();
            GoToPage(m_currentPage);
        }
        if (m_pages.empty()) {
            SignalLoadComplete(0, 0, 0);
        }
        else {
            SignalLoadComplete(m_pages.size(), m_pages.front().width, m_pages.front().height);
        }
        // Render low-res preview of the pages
        double useScale = (std::min)(m_scale, m_previewZoom);
        for (unsigned page = 0; page < m_pages.size(); ++page) {
            co_await m_pages[page].render(useScale);
        }
    }
  }

  //winrt::fire_and_forget RCTPdfControl::Rescale(double newScale, double newMargin, bool goToNewPosition) {
  winrt::fire_and_forget RCTPdfControl::Rescale(double newScale, double newMargin, bool goToNewPosition) {
      //co_await m_pages[0].render(newScale);
      if (newScale != m_scale || newMargin != m_margins) {
      double rescale = newScale / m_scale;
      double targetHorizontalOffset = PagesContainer().HorizontalOffset() * rescale;
      double targetVerticalOffset = PagesContainer().VerticalOffset() * rescale;

      if (newMargin != m_margins) {
        if (m_horizontal) {
          targetVerticalOffset += (double)m_currentPage * 2 * (newMargin - m_margins) * rescale;
        }
        else {
          targetHorizontalOffset += (double)m_currentPage * 2 * (newMargin - m_margins) * rescale;
        }
      }
      m_scale = newScale;
      m_margins = (int)newMargin;
      UpdatePagesInfoMarginOrScale();
      UpdateHotspots();
      UpdateNotes();
      UpdateTextNotes();
      if (goToNewPosition) {
        ChangeScroll(targetHorizontalOffset, targetVerticalOffset);
      }
      co_await m_pages[0].render(newScale);
    }
  }

  void RCTPdfControl::SetOrientation(bool horizontal) {
    m_horizontal = horizontal;
    StackPanel orientationSelector;
    if (FindName(winrt::to_hstring("OrientationSelector")).try_as<StackPanel>(orientationSelector))
    {
      orientationSelector.Orientation(m_horizontal ? Orientation::Horizontal : Orientation::Vertical);
    }
  }

  winrt::Windows::Foundation::IAsyncAction RCTPdfControl::RenderVisiblePages(int page) {
    auto lifetime = get_strong();
    auto container = PagesContainer();
    auto currentHorizontalOffset = container.HorizontalOffset();
    auto currentVerticalOffset = container.VerticalOffset();

    double offsetStart = m_horizontal ? currentHorizontalOffset : currentVerticalOffset;

    auto viewWidth = container.ViewportWidth();
    auto viewHeight = container.ViewportHeight();
    

    double viewSize = m_horizontal ? viewWidth : viewHeight;
    double offsetEnd = offsetStart + viewSize;
    if (m_pages[page].needsRender()) {
      co_await m_pages[page].render();
    }
    auto pageToRender = page + 1;
    while (pageToRender < (int)m_pages.size() &&
      m_pages[pageToRender].pageVisiblePixels(m_horizontal, offsetStart, offsetEnd) > 0) {
      if (m_pages[pageToRender].needsRender()) {
        co_await m_pages[pageToRender].render();
      }
      ++pageToRender;
    }
    if (pageToRender < (int)m_pages.size() && m_pages[pageToRender].needsRender()) {
      co_await m_pages[pageToRender].render();
    }
    if (page >= 1 && m_pages[page - 1].needsRender()) {
      co_await m_pages[page - 1].render();
    }
    if (page >= 2 && m_pages[page - 2].needsRender()) {
      co_await m_pages[page - 2].render();
    }
  }

  void RCTPdfControl::SignalError(const std::string& error) {
    m_reactContext.DispatchEvent(
      *this,
      L"topChange",
      [&](winrt::Microsoft::ReactNative::IJSValueWriter const& eventDataWriter) noexcept {
        eventDataWriter.WriteObjectBegin();
        {
          WriteProperty(eventDataWriter, L"message", winrt::to_hstring("error|" + error));
        }
        eventDataWriter.WriteObjectEnd();
      });
  }
  void RCTPdfControl::SignalLoadComplete(int totalPages, int width, int height) {
    auto message = "loadComplete|" +
                   std::to_string(totalPages) + "|" +
                   std::to_string(width) + "|" +
                   std::to_string(height) + "|" +
                   std::to_string(m_scale);
    m_reactContext.DispatchEvent(
      *this,
      L"topChange",
      [&](winrt::Microsoft::ReactNative::IJSValueWriter const& eventDataWriter) noexcept {
        eventDataWriter.WriteObjectBegin();
        {
          WriteProperty(eventDataWriter, L"message", winrt::to_hstring(message));
        }
        eventDataWriter.WriteObjectEnd();
      });
  }
  void RCTPdfControl::SignalPageChange(int page, int totalPages) {
    auto message = "pageChanged|" + std::to_string(page) + "|" + std::to_string(totalPages);
    m_reactContext.DispatchEvent(
      *this,
      L"topChange",
      [&](winrt::Microsoft::ReactNative::IJSValueWriter const& eventDataWriter) noexcept {
        eventDataWriter.WriteObjectBegin();
        {
          WriteProperty(eventDataWriter, L"message", winrt::to_hstring(message));
        }
        eventDataWriter.WriteObjectEnd();
      });
  }
  void RCTPdfControl::SignalScaleChanged(double scale, double offsetX, double offsetY) {
    m_reactContext.DispatchEvent(
      *this,
      L"topChange",
      [&](winrt::Microsoft::ReactNative::IJSValueWriter const& eventDataWriter) noexcept {
        eventDataWriter.WriteObjectBegin();
        {
          WriteProperty(eventDataWriter, L"message", winrt::to_hstring("scaleChanged|" + std::to_string(scale) + "|" + std::to_string(offsetX) + "|" + std::to_string(offsetY)));
        }
        eventDataWriter.WriteObjectEnd();
      });
  }
  void RCTPdfControl::SignalPageTapped(int page, int x, int y) {
    const std::string message = "pageSingleTap|" +
                                std::to_string(page + 1) + "|" +
                                std::to_string(x) + "|" +
                                std::to_string(y);
    m_reactContext.DispatchEvent(
      *this,
      L"topChange",
      [&](winrt::Microsoft::ReactNative::IJSValueWriter const& eventDataWriter) noexcept {
        eventDataWriter.WriteObjectBegin();
        {
          WriteProperty(eventDataWriter, L"message", winrt::to_hstring(message));
        }
        eventDataWriter.WriteObjectEnd();
      });
  }

  void RCTPdfControl::UpdateHotspots() {
    if (m_pages.empty()) return;

    Canvas hotspotsCanvas;
    if (!FindName(winrt::to_hstring("HotspotsCanvas")).try_as<Canvas>(hotspotsCanvas)) return;

    hotspotsCanvas.Children().Clear();

    double scaledMargin = m_scale * m_margins;
    double contentWidth = 0;
    double contentHeight = 0;
    {
      std::shared_lock lock(m_rwlock);
      if (m_horizontal) {
        auto& lastPage = m_pages.back();
        contentWidth = (double)lastPage.scaledLeftOffset + (double)lastPage.scaledWidth + 2.0 * scaledMargin;
        for (auto& page : m_pages) {
          contentHeight = (std::max)(contentHeight, (double)page.scaledHeight + 2.0 * scaledMargin);
        }
      } else {
        for (auto& page : m_pages) {
          contentWidth = (std::max)(contentWidth, (double)page.scaledWidth + 2.0 * scaledMargin);
        }
        auto& lastPage = m_pages.back();
        contentHeight = (double)lastPage.scaledTopOffset + (double)lastPage.scaledHeight + 2.0 * scaledMargin;
      }
    }

    hotspotsCanvas.Width(contentWidth);
    hotspotsCanvas.Height(contentHeight);
    double scaledHotspotSize = m_hotspotSize * m_scale;

    for (auto& hotspot : m_hotspots) {
      Image img;
      img.Width(scaledHotspotSize);
      img.Height(scaledHotspotSize);

      SvgImageSource svgSource;
      svgSource.UriSource(Uri(L"ms-appx:///Assets/images/classification_" + winrt::to_hstring(hotspot.type) + L".svg"));
      img.Source(svgSource);

      Canvas::SetLeft(img, contentWidth  * hotspot.xPos);
      Canvas::SetTop(img,  contentHeight * hotspot.yPos);

      auto uid = hotspot.uid;
      img.Tapped([this, uid](winrt::Windows::Foundation::IInspectable const&, winrt::Windows::UI::Xaml::Input::TappedRoutedEventArgs const& e) {
        SignalHotspotPress(uid);
        e.Handled(true);
      });

      hotspotsCanvas.Children().Append(img);
    }
  }

  void RCTPdfControl::UpdateNotes() {
    if (m_pages.empty()) return;

    Canvas notesCanvas;
    if (!FindName(winrt::to_hstring("NotesCanvas")).try_as<Canvas>(notesCanvas)) return;

    double scaledMargin = m_scale * m_margins;
    double contentWidth = 0;
    double contentHeight = 0;
    {
      std::shared_lock lock(m_rwlock);
      if (m_horizontal) {
        auto& lastPage = m_pages.back();
        contentWidth = (double)lastPage.scaledLeftOffset + (double)lastPage.scaledWidth + 2.0 * scaledMargin;
        for (auto& page : m_pages)
          contentHeight = (std::max)(contentHeight, (double)page.scaledHeight + 2.0 * scaledMargin);
      } else {
        for (auto& page : m_pages)
          contentWidth = (std::max)(contentWidth, (double)page.scaledWidth + 2.0 * scaledMargin);
        auto& lastPage = m_pages.back();
        contentHeight = (double)lastPage.scaledTopOffset + (double)lastPage.scaledHeight + 2.0 * scaledMargin;
      }
    }

    notesCanvas.Width(contentWidth);
    notesCanvas.Height(contentHeight);
    m_notesContentWidth  = contentWidth;
    m_notesContentHeight = contentHeight;

    // Remove notes that no longer exist
    std::set<std::string> activeUids;
    for (auto& note : m_notes) activeUids.insert(note.uid);
    std::vector<std::string> toRemove;
    for (auto& [uid, img] : m_noteImages) {
      if (activeUids.find(uid) == activeUids.end()) {
        toRemove.push_back(uid);
        uint32_t idx;
        if (notesCanvas.Children().IndexOf(img, idx))
          notesCanvas.Children().RemoveAt(idx);
      }
    }
    for (auto& uid : toRemove) {
      m_noteImages.erase(uid);
      m_noteInfoCache.erase(uid);
    }

    struct DragState {
      double startPointerX = 0, startPointerY = 0;
      double startLeft = 0,     startTop = 0;
      bool   dragging  = false, moved    = false;
    };
    static constexpr double dragThreshold = 4.0;

    for (auto& note : m_notes) {
      double left = contentWidth  * note.xPos - m_noteSize / 2.0;
      double top  = contentHeight * note.yPos - m_noteSize / 2.0;

      auto it = m_noteImages.find(note.uid);
      if (it != m_noteImages.end()) {
        // Existing note — always reposition (contentWidth/Height change with zoom)
        auto& img    = it->second;
        auto& cached = m_noteInfoCache[note.uid];
        Canvas::SetLeft(img, left);
        Canvas::SetTop(img,  top);
        // Only reload SVG if color changed (avoids flicker)
        if (cached.color != note.color) {
          SvgImageSource svgSource;
          svgSource.UriSource(Uri(L"ms-appx:///Assets/images/annotation_" + winrt::to_hstring(note.color) + L".svg"));
          img.Source(svgSource);
        }
        m_noteInfoCache[note.uid] = note;
      } else {
        // New note — create element and attach events
        Image noteIcon;
        noteIcon.Width(m_noteSize);
        noteIcon.Height(m_noteSize);
        noteIcon.IsHitTestVisible(true);

        SvgImageSource svgSource;
        svgSource.UriSource(Uri(L"ms-appx:///Assets/images/annotation_" + winrt::to_hstring(note.color) + L".svg"));
        noteIcon.Source(svgSource);

        Canvas::SetLeft(noteIcon, left);
        Canvas::SetTop(noteIcon,  top);

        auto uid  = note.uid;
        auto drag = std::make_shared<DragState>();

        noteIcon.PointerPressed([this, noteIcon, drag](winrt::Windows::Foundation::IInspectable const&, winrt::Windows::UI::Xaml::Input::PointerRoutedEventArgs const& e) mutable {
          auto pos = e.GetCurrentPoint(*this).Position();
          drag->startPointerX = pos.X + PagesContainer().HorizontalOffset();
          drag->startPointerY = pos.Y + PagesContainer().VerticalOffset();
          drag->startLeft = Canvas::GetLeft(noteIcon);
          drag->startTop  = Canvas::GetTop(noteIcon);
          drag->dragging  = true;
          drag->moved     = false;
          noteIcon.CapturePointer(e.Pointer());
          e.Handled(true);
        });

        noteIcon.PointerMoved([this, noteIcon, drag](winrt::Windows::Foundation::IInspectable const&, winrt::Windows::UI::Xaml::Input::PointerRoutedEventArgs const& e) mutable {
          if (!drag->dragging) return;
          auto pos = e.GetCurrentPoint(*this).Position();
          double contentX = pos.X + PagesContainer().HorizontalOffset();
          double contentY = pos.Y + PagesContainer().VerticalOffset();
          double newLeft  = drag->startLeft + (contentX - drag->startPointerX);
          double newTop   = drag->startTop  + (contentY - drag->startPointerY);
          if (std::abs(newLeft - drag->startLeft) > dragThreshold ||
              std::abs(newTop  - drag->startTop)  > dragThreshold)
            drag->moved = true;
          Canvas::SetLeft(noteIcon, (std::min)((std::max)(0.0, newLeft), m_notesContentWidth  - m_noteSize));
          Canvas::SetTop(noteIcon,  (std::min)((std::max)(0.0, newTop),  m_notesContentHeight - m_noteSize));
          e.Handled(true);
        });

        noteIcon.PointerReleased([this, noteIcon, drag, uid](winrt::Windows::Foundation::IInspectable const&, winrt::Windows::UI::Xaml::Input::PointerRoutedEventArgs const& e) mutable {
          if (!drag->dragging) return;
          drag->dragging = false;
          noteIcon.ReleasePointerCapture(e.Pointer());
          if (drag->moved) {
            double xPercent = m_notesContentWidth  > 0 ? (Canvas::GetLeft(noteIcon) + m_noteSize / 2.0) / m_notesContentWidth  * 100.0 : 0;
            double yPercent = m_notesContentHeight > 0 ? (Canvas::GetTop(noteIcon)  + m_noteSize / 2.0) / m_notesContentHeight * 100.0 : 0;
            SignalNoteMoved(uid, xPercent, yPercent);
          } else {
            auto transform   = noteIcon.TransformToVisual(*this);
            auto pointInView = transform.TransformPoint(winrt::Windows::Foundation::Point((float)(m_noteSize / 2.0), (float)(m_noteSize / 2.0)));
            double xPercent  = ActualWidth()  > 0 ? (double)pointInView.X / ActualWidth()  * 100.0 : 0;
            double yPercent  = ActualHeight() > 0 ? (double)pointInView.Y / ActualHeight() * 100.0 : 0;
            SignalNotePress(uid, xPercent, yPercent);
          }
          e.Handled(true);
        });

        noteIcon.PointerCaptureLost([drag](winrt::Windows::Foundation::IInspectable const&, winrt::Windows::UI::Xaml::Input::PointerRoutedEventArgs const&) mutable {
          drag->dragging = false;
        });

        notesCanvas.Children().Append(noteIcon);
        m_noteImages[note.uid]    = noteIcon;
        m_noteInfoCache[note.uid] = note;
      }
    }
  }

  void RCTPdfControl::UpdateTextNotes() {
    if (m_pages.empty()) return;

    Canvas textNotesCanvas;
    if (!FindName(winrt::to_hstring("TextNotesCanvas")).try_as<Canvas>(textNotesCanvas)) return;

    double scaledMargin = m_scale * m_margins;
    double contentWidth = 0;
    double contentHeight = 0;
    {
      std::shared_lock lock(m_rwlock);
      if (m_horizontal) {
        auto& lastPage = m_pages.back();
        contentWidth = (double)lastPage.scaledLeftOffset + (double)lastPage.scaledWidth + 2.0 * scaledMargin;
        for (auto& page : m_pages)
          contentHeight = (std::max)(contentHeight, (double)page.scaledHeight + 2.0 * scaledMargin);
      } else {
        for (auto& page : m_pages)
          contentWidth = (std::max)(contentWidth, (double)page.scaledWidth + 2.0 * scaledMargin);
        auto& lastPage = m_pages.back();
        contentHeight = (double)lastPage.scaledTopOffset + (double)lastPage.scaledHeight + 2.0 * scaledMargin;
      }
    }

    textNotesCanvas.Width(contentWidth);
    textNotesCanvas.Height(contentHeight);
    m_textNotesContentWidth  = contentWidth;
    m_textNotesContentHeight = contentHeight;

    // Clear and rebuild all elements
    textNotesCanvas.Children().Clear();
    m_textNoteElements.clear();
    m_textNoteInfoCache.clear();
    m_textNoteEditModeSetters.clear();
    m_textNoteTextEditSetters.clear();

    // ── State structs ────────────────────────────────────────────────────────
    struct DragState {
      double startPointerX = 0, startPointerY = 0;
      double startLeft = 0,     startTop = 0;
      bool   dragging  = false, moved    = false;
    };
    struct ResizeState {
      double startPX = 0, startPY = 0;
      double startNoteW = 0, startNoteH = 0;
      double startContainerT = 0, startContainerL = 0;
      bool   dragging = false;
    };

    // ── Constants ────────────────────────────────────────────────────────────
    static constexpr double dragThreshold   = 4.0;
    static constexpr double kLeftMargin     = 33.0;
    static constexpr double kTopMargin      = 16.0;
    static constexpr double kRightMargin    = 13.0;
    static constexpr double kBottomMargin   = 16.0;
    static constexpr double kBorderOffset   = 5.0;
    static constexpr double kBtnSize        = 16.0;
    static constexpr double kMinNoteW       = 50.0;
    static constexpr double kMinNoteH       = 30.0;
    static constexpr int    kResizeTopMid     = 0;
    static constexpr int    kResizeTopRight   = 1;
    static constexpr int    kResizeMidRight   = 2;
    static constexpr int    kResizeBottomRight= 3;
    static constexpr int    kResizeBottomMid  = 4;

    Windows::UI::Color btnColor{ 230, 51, 128, 230 };
    Windows::UI::Color dashColor{ 255, 51, 102, 204 };

    for (auto& note : m_textNotes) {
      double noteW = contentWidth  * note.width;
      double noteH = contentHeight * note.height;
      double noteL = contentWidth  * note.xPos;
      double noteT = contentHeight * note.yPos;
      double bs2   = 2.0 * note.borderSize;

      // ── Container Canvas ─────────────────────────────────────────────────
      Canvas container;
      container.Width (noteW + 6 + bs2 + kLeftMargin + kRightMargin);
      container.Height(noteH + 6 + bs2 + kTopMargin  + kBottomMargin);
      container.Background(SolidColorBrush(Windows::UI::Colors::Transparent()));
      container.IsHitTestVisible(true);
      Canvas::SetLeft(container, noteL - kLeftMargin);
      Canvas::SetTop (container, noteT - kTopMargin);

      // ── Note Border (3001) ───────────────────────────────────────────────
      // parseColor is declared here so it can be reused by the editBox below
      auto parseColor = [](const std::string& colorStr, double opacity) -> SolidColorBrush {
        Windows::UI::Color c;
        bool isTransparent = colorStr == "transparent" || colorStr.empty();
        if (isTransparent) {
          c = Windows::UI::Colors::Transparent();
        } else {
          std::string hex = colorStr;
          if (!hex.empty() && hex[0] == '#') hex = hex.substr(1);
          try {
            uint32_t val = std::stoul(hex, nullptr, 16);
            if (hex.size() == 8) {
              c.A = (val >> 24) & 0xFF;
              c.R = (val >> 16) & 0xFF;
              c.G = (val >> 8)  & 0xFF;
              c.B =  val        & 0xFF;
            } else {
              c.A = 255;
              c.R = (val >> 16) & 0xFF;
              c.G = (val >> 8)  & 0xFF;
              c.B =  val        & 0xFF;
            }
          } catch (...) {
            c = Windows::UI::Colors::Transparent();
          }
        }
        SolidColorBrush brush(c);
        brush.Opacity(opacity);
        return brush;
      };

      Border noteBorder;
      noteBorder.Width (noteW + 6 + bs2);
      noteBorder.Height(noteH + 6 + bs2);
      noteBorder.Background(parseColor(note.backgroundColor, note.backgroundOpacity));
      if (note.borderSize > 0) {
        noteBorder.BorderBrush(parseColor(note.borderColor, note.borderOpacity));
        noteBorder.BorderThickness(ThicknessHelper::FromUniformLength(note.borderSize));
      } else {
        noteBorder.BorderThickness(ThicknessHelper::FromUniformLength(0));
      }
      noteBorder.IsHitTestVisible(false);
      noteBorder.Padding(ThicknessHelper::FromUniformLength(4.0));
      Canvas::SetLeft(noteBorder, kLeftMargin);
      Canvas::SetTop (noteBorder, kTopMargin);
      container.Children().Append(noteBorder);
      // ── TextBox: single control for both display and edit ─────────────────
      // IsReadOnly=true for display, IsReadOnly=false for editing.
      // Using one control avoids any rendering difference when switching modes.
      TextBox editBox;
      editBox.AcceptsReturn(true);
      editBox.TextWrapping(TextWrapping::Wrap);
      editBox.IsReadOnly(true);
      editBox.IsHitTestVisible(false);
      editBox.BorderThickness(ThicknessHelper::FromUniformLength(0));
      ScrollViewer::SetHorizontalScrollBarVisibility(editBox, ScrollBarVisibility::Disabled);
      ScrollViewer::SetVerticalScrollBarVisibility  (editBox, ScrollBarVisibility::Disabled);
      {
        SolidColorBrush transparent(Windows::UI::Colors::Transparent());
        editBox.Background(transparent);
        std::string fgHex = note.lines.empty() ? "#000000" : note.lines[0].fontColor;
        double fgOpacity  = note.lines.empty() ? 1.0       : note.lines[0].fontOpacity;
        auto noteFg = parseColor(fgHex.empty() ? "#000000" : fgHex, fgOpacity);
        editBox.Foreground(noteFg);
        // Override all visual-state brushes so nothing changes between
        // ReadOnly, PointerOver, Focused, and Disabled states.
        auto& res = editBox.Resources();
        res.Insert(winrt::box_value(L"TextControlBackground"),             transparent);
        res.Insert(winrt::box_value(L"TextControlBackgroundPointerOver"),  transparent);
        res.Insert(winrt::box_value(L"TextControlBackgroundFocused"),      transparent);
        res.Insert(winrt::box_value(L"TextControlBackgroundReadOnly"),     transparent);
        res.Insert(winrt::box_value(L"TextControlBackgroundDisabled"),     transparent);
        res.Insert(winrt::box_value(L"TextControlBorderBrush"),            transparent);
        res.Insert(winrt::box_value(L"TextControlBorderBrushPointerOver"), transparent);
        res.Insert(winrt::box_value(L"TextControlBorderBrushFocused"),     transparent);
        res.Insert(winrt::box_value(L"TextControlBorderBrushDisabled"),    transparent);
        res.Insert(winrt::box_value(L"TextControlForeground"),             noteFg);
        res.Insert(winrt::box_value(L"TextControlForegroundPointerOver"),  noteFg);
        res.Insert(winrt::box_value(L"TextControlForegroundFocused"),      noteFg);
        res.Insert(winrt::box_value(L"TextControlForegroundReadOnly"),     noteFg);
        res.Insert(winrt::box_value(L"TextControlForegroundDisabled"),     noteFg);
      }
      editBox.Padding(ThicknessHelper::FromUniformLength(4.0));
      editBox.Width (noteW + 6);
      editBox.Height(noteH + 6);
      if (!note.lines.empty() && note.lines[0].fontSize > 0)
        editBox.FontSize(note.lines[0].fontSize * m_scale * 0.85);
      {
        std::wstring fullText;
        for (size_t li = 0; li < note.lines.size(); ++li) {
          if (li > 0) fullText += L"\n";
          fullText += winrt::to_hstring(note.lines[li].text);
        }
        editBox.Text(winrt::hstring(fullText));
      }
      Canvas::SetLeft(editBox, kLeftMargin + bs2 / 2.0);
      Canvas::SetTop (editBox, kTopMargin  + bs2 / 2.0);
      container.Children().Append(editBox);

      // ── Dashed selection border (4007) ───────────────────────────────────
      Rectangle selBorder;
      selBorder.Width (noteW + 6 + bs2 + kBorderOffset * 2);
      selBorder.Height(noteH + 6 + bs2 + kBorderOffset * 2);
      selBorder.Fill(SolidColorBrush(Windows::UI::Colors::Transparent()));
      selBorder.Stroke(SolidColorBrush(dashColor));
      selBorder.StrokeThickness(2.0);
      selBorder.StrokeDashArray().Append(4.0f);
      selBorder.StrokeDashArray().Append(4.0f);
      selBorder.IsHitTestVisible(false);
      selBorder.Visibility(Visibility::Collapsed);
      Canvas::SetLeft(selBorder, kLeftMargin - kBorderOffset);
      Canvas::SetTop (selBorder, kTopMargin  - kBorderOffset);
      container.Children().Append(selBorder);

      // ── Resize handles (4001–4005) — IsHitTestVisible=true for pointer events
      auto makeHandle = [&](double cx, double cy) -> Ellipse {
        Ellipse handle;
        handle.Width (kBtnSize);
        handle.Height(kBtnSize);
        handle.Fill(SolidColorBrush(btnColor));
        handle.IsHitTestVisible(true);
        handle.Visibility(Visibility::Collapsed);
        Canvas::SetLeft(handle, cx - kBtnSize / 2);
        Canvas::SetTop (handle, cy - kBtnSize / 2);
        container.Children().Append(handle);
        return handle;
      };
      Ellipse hTopMid      = makeHandle(kLeftMargin + (noteW + 6 + bs2) / 2,
                                        kTopMargin  - kBorderOffset);
      Ellipse hTopRight    = makeHandle(kLeftMargin + noteW + 6 + bs2 + kBorderOffset,
                                        kTopMargin  - kBorderOffset);
      Ellipse hMidRight    = makeHandle(kLeftMargin + noteW + 6 + bs2 + kBorderOffset,
                                        kTopMargin  + (noteH + 6 + bs2) / 2);
      Ellipse hBottomRight = makeHandle(kLeftMargin + noteW + 6 + bs2 + kBorderOffset,
                                        kTopMargin  + noteH + 6 + bs2 + kBorderOffset);
      Ellipse hBottomMid   = makeHandle(kLeftMargin + (noteW + 6 + bs2) / 2,
                                        kTopMargin  + noteH + 6 + bs2 + kBorderOffset);

      // ── Side drag bar (4006) ─────────────────────────────────────────────
      double sideW = kLeftMargin - kBorderOffset;
      double sideH = noteH + 6 + bs2 + kBorderOffset * 2;
      Border sideView;
      sideView.Width (sideW);
      sideView.Height(sideH);
      sideView.Background(SolidColorBrush(btnColor));
      sideView.CornerRadius(CornerRadiusHelper::FromUniformRadius(4.0));
      sideView.IsHitTestVisible(false);
      Canvas::SetLeft(sideView, 0);
      Canvas::SetTop (sideView, kTopMargin - kBorderOffset);
      Canvas sideContent;
      sideContent.Width (sideW);
      sideContent.Height(sideH);
      double lineW = sideW * 0.5;
      double lineX = (sideW - lineW) / 2;
      for (int i = 0; i < 3; i++) {
        Border line;
        line.Width (lineW);
        line.Height(2.0);
        line.Background(SolidColorBrush(Windows::UI::Colors::White()));
        line.CornerRadius(CornerRadiusHelper::FromUniformRadius(1.0));
        Canvas::SetLeft(line, lineX);
        Canvas::SetTop (line, sideH / 2 - 6 + i * 5);
        sideContent.Children().Append(line);
      }
      sideView.Child(sideContent);
      sideView.Visibility(Visibility::Collapsed);
      container.Children().Append(sideView);

      // ── Edit mode setter ─────────────────────────────────────────────────
      m_textNoteEditModeSetters[note.uid] =
        [selBorder, hTopMid, hTopRight, hMidRight, hBottomRight, hBottomMid, sideView]
        (bool visible) mutable {
          auto vis = visible ? Visibility::Visible : Visibility::Collapsed;
          selBorder.Visibility(vis);
          hTopMid.Visibility(vis);
          hTopRight.Visibility(vis);
          hMidRight.Visibility(vis);
          hBottomRight.Visibility(vis);
          hBottomMid.Visibility(vis);
          sideView.Visibility(vis);
        };
      m_textNoteTextEditSetters[note.uid] =
        [editBox](bool active) mutable {
          editBox.IsReadOnly(!active);
          editBox.IsHitTestVisible(active);
          if (active) editBox.Focus(FocusState::Programmatic);
        };

      // ── Shared relayout: updates all elements after a resize ─────────────
      // nW, nH = new noteBorder dimensions (including the +6 padding)
      auto relayout = std::make_shared<std::function<void(double, double)>>(
        [container, noteBorder, selBorder,
         hTopMid, hTopRight, hMidRight, hBottomRight, hBottomMid,
         sideView, sideContent, editBox, bs2]
        (double nW, double nH) mutable {
          noteBorder.Width (nW);
          noteBorder.Height(nH);
          selBorder.Width (nW + kBorderOffset * 2);
          selBorder.Height(nH + kBorderOffset * 2);

          Canvas::SetLeft(hTopMid,      kLeftMargin + nW / 2            - kBtnSize / 2);
          Canvas::SetTop (hTopMid,      kTopMargin  - kBorderOffset      - kBtnSize / 2);
          Canvas::SetLeft(hTopRight,    kLeftMargin + nW + kBorderOffset - kBtnSize / 2);
          Canvas::SetTop (hTopRight,    kTopMargin  - kBorderOffset      - kBtnSize / 2);
          Canvas::SetLeft(hMidRight,    kLeftMargin + nW + kBorderOffset - kBtnSize / 2);
          Canvas::SetTop (hMidRight,    kTopMargin  + nH / 2             - kBtnSize / 2);
          Canvas::SetLeft(hBottomRight, kLeftMargin + nW + kBorderOffset - kBtnSize / 2);
          Canvas::SetTop (hBottomRight, kTopMargin  + nH + kBorderOffset - kBtnSize / 2);
          Canvas::SetLeft(hBottomMid,   kLeftMargin + nW / 2            - kBtnSize / 2);
          Canvas::SetTop (hBottomMid,   kTopMargin  + nH + kBorderOffset - kBtnSize / 2);

          double newSideH = nH + kBorderOffset * 2;
          sideView.Height(newSideH);
          sideContent.Height(newSideH);
          uint32_t li = 0;
          for (uint32_t i = 0; i < sideContent.Children().Size(); i++) {
            if (auto ln = sideContent.Children().GetAt(i).try_as<Border>()) {
              Canvas::SetTop(ln, newSideH / 2 - 6 + (double)li * 5);
              li++;
            }
          }
          container.Width (nW + kLeftMargin + kRightMargin);
          container.Height(nH + kTopMargin  + kBottomMargin);
          editBox.Width (nW - bs2);
          editBox.Height(nH - bs2);
        }
      );

      // ── Resize event helper ──────────────────────────────────────────────
      auto uid = note.uid;
      auto attachResize = [this, container, noteBorder, relayout, uid, bs2]
                          (Ellipse handle, int resizeType) {
        auto rs = std::make_shared<ResizeState>();

        handle.PointerPressed(
          [this, handle, container, noteBorder, rs]
          (winrt::Windows::Foundation::IInspectable const&,
           winrt::Windows::UI::Xaml::Input::PointerRoutedEventArgs const& e) mutable {
            auto pos = e.GetCurrentPoint(*this).Position();
            rs->startPX         = pos.X + PagesContainer().HorizontalOffset();
            rs->startPY         = pos.Y + PagesContainer().VerticalOffset();
            rs->startNoteW      = noteBorder.Width();
            rs->startNoteH      = noteBorder.Height();
            rs->startContainerT = Canvas::GetTop(container);
            rs->startContainerL = Canvas::GetLeft(container);
            rs->dragging        = true;
            handle.CapturePointer(e.Pointer());
            e.Handled(true);
        });

        handle.PointerMoved(
          [this, container, rs, relayout, resizeType, bs2]
          (winrt::Windows::Foundation::IInspectable const&,
           winrt::Windows::UI::Xaml::Input::PointerRoutedEventArgs const& e) mutable {
            if (!rs->dragging) return;
            auto pos  = e.GetCurrentPoint(*this).Position();
            double dX = pos.X + PagesContainer().HorizontalOffset() - rs->startPX;
            double dY = pos.Y + PagesContainer().VerticalOffset()   - rs->startPY;
            double nW = rs->startNoteW, nH = rs->startNoteH;
            switch (resizeType) {
              case kResizeTopMid:      nH = rs->startNoteH - dY; break;
              case kResizeTopRight:    nW = rs->startNoteW + dX;
                                       nH = rs->startNoteH - dY; break;
              case kResizeMidRight:    nW = rs->startNoteW + dX; break;
              case kResizeBottomRight: nW = rs->startNoteW + dX;
                                       nH = rs->startNoteH + dY; break;
              case kResizeBottomMid:   nH = rs->startNoteH + dY; break;
            }
            // Clamp right boundary: note right edge cannot exceed contentWidth
            if (m_textNotesContentWidth > 0) {
              double noteLeft = rs->startContainerL + kLeftMargin;
              double maxNW = m_textNotesContentWidth - noteLeft;
              if (nW > maxNW) nW = maxNW;
            }
            // Clamp top/bottom boundary
            bool isTopHandle = (resizeType == kResizeTopMid || resizeType == kResizeTopRight);
            if (isTopHandle) {
              // Container can go as high as -kTopMargin (note top = 0)
              double maxNH = rs->startContainerT + rs->startNoteH + kTopMargin;
              if (m_textNotesContentHeight > 0 && nH > maxNH) nH = maxNH;
            } else {
              // Note bottom cannot exceed contentHeight
              double noteTop = rs->startContainerT + kTopMargin;
              double maxNH = m_textNotesContentHeight - noteTop;
              if (m_textNotesContentHeight > 0 && nH > maxNH) nH = maxNH;
            }
            // Apply minimum size
            if (nW < kMinNoteW + 6 + bs2) nW = kMinNoteW + 6 + bs2;
            if (nH < kMinNoteH + 6 + bs2) nH = kMinNoteH + 6 + bs2;
            // deltaT is derived from the final clamped nH (top handles only)
            double deltaT = isTopHandle ? rs->startNoteH - nH : 0;
            (*relayout)(nW, nH);
            Canvas::SetTop(container, rs->startContainerT + deltaT);
            e.Handled(true);
        });

        handle.PointerReleased(
          [this, handle, container, noteBorder, rs, uid, bs2]
          (winrt::Windows::Foundation::IInspectable const&,
           winrt::Windows::UI::Xaml::Input::PointerRoutedEventArgs const& e) mutable {
            if (!rs->dragging) return;
            rs->dragging = false;
            handle.ReleasePointerCapture(e.Pointer());
            double noteLeft = Canvas::GetLeft(container) + kLeftMargin;
            double noteTop  = Canvas::GetTop (container) + kTopMargin;
            double xPct = m_textNotesContentWidth  > 0 ? noteLeft / m_textNotesContentWidth  * 100.0 : 0.0;
            double yPct = m_textNotesContentHeight > 0 ? noteTop  / m_textNotesContentHeight * 100.0 : 0.0;
            double wPct = m_textNotesContentWidth  > 0 ? (noteBorder.Width()  - 6 - bs2) / m_textNotesContentWidth  * 100.0 : 0.0;
            double hPct = m_textNotesContentHeight > 0 ? (noteBorder.Height() - 6 - bs2) / m_textNotesContentHeight * 100.0 : 0.0;
            std::string msg = "noteMoved|" + uid + "|" + std::to_string(xPct) + "|" +
                              std::to_string(yPct) + "|" + std::to_string(wPct) + "|" +
                              std::to_string(hPct);
            m_reactContext.DispatchEvent(*this, L"topChange",
              [msg](winrt::Microsoft::ReactNative::IJSValueWriter const& w) noexcept {
                w.WriteObjectBegin();
                WriteProperty(w, L"message", winrt::to_hstring(msg));
                w.WriteObjectEnd();
              });
            e.Handled(true);
        });

        handle.PointerCaptureLost(
          [rs](winrt::Windows::Foundation::IInspectable const&,
               winrt::Windows::UI::Xaml::Input::PointerRoutedEventArgs const&) mutable {
            rs->dragging = false;
        });
      };

      attachResize(hTopMid,      kResizeTopMid);
      attachResize(hTopRight,    kResizeTopRight);
      attachResize(hMidRight,    kResizeMidRight);
      attachResize(hBottomRight, kResizeBottomRight);
      attachResize(hBottomMid,   kResizeBottomMid);

      // ── Drag events on container ─────────────────────────────────────────
      auto drag = std::make_shared<DragState>();

      container.PointerPressed([this, container, drag](winrt::Windows::Foundation::IInspectable const&, winrt::Windows::UI::Xaml::Input::PointerRoutedEventArgs const& e) mutable {
        auto pos = e.GetCurrentPoint(*this).Position();
        drag->startPointerX = pos.X + PagesContainer().HorizontalOffset();
        drag->startPointerY = pos.Y + PagesContainer().VerticalOffset();
        drag->startLeft = Canvas::GetLeft(container);
        drag->startTop  = Canvas::GetTop (container);
        drag->dragging  = true;
        drag->moved     = false;
        container.CapturePointer(e.Pointer());
        e.Handled(true);
      });

      container.PointerMoved([this, container, drag, uid](winrt::Windows::Foundation::IInspectable const&, winrt::Windows::UI::Xaml::Input::PointerRoutedEventArgs const& e) mutable {
        if (!drag->dragging) return;
        auto pos    = e.GetCurrentPoint(*this).Position();
        double cX   = pos.X + PagesContainer().HorizontalOffset();
        double cY   = pos.Y + PagesContainer().VerticalOffset();
        double newL = drag->startLeft + (cX - drag->startPointerX);
        double newT = drag->startTop  + (cY - drag->startPointerY);
        if (!drag->moved &&
            (std::abs(newL - drag->startLeft) > dragThreshold ||
             std::abs(newT - drag->startTop)  > dragThreshold)) {
          drag->moved = true;
          for (auto& [u, setter] : m_textNoteEditModeSetters) setter(false);
          m_textNoteEditModeSetters[uid](true);
          m_activeTextNoteUid = uid;
        }
        double maxL = m_textNotesContentWidth  > 0 ? m_textNotesContentWidth  - container.Width()  + kRightMargin : 0.0;
        double maxT = m_textNotesContentHeight > 0 ? m_textNotesContentHeight - container.Height() + kBottomMargin : 0.0;
        Canvas::SetLeft(container, (std::min)((std::max)(-kLeftMargin, newL), maxL));
        Canvas::SetTop (container, (std::min)((std::max)(-kTopMargin,  newT), maxT));
        e.Handled(true);
      });

      container.PointerReleased([this, container, noteBorder, drag, uid, bs2](winrt::Windows::Foundation::IInspectable const&, winrt::Windows::UI::Xaml::Input::PointerRoutedEventArgs const& e) mutable {
        if (!drag->dragging) return;
        drag->dragging = false;
        container.ReleasePointerCapture(e.Pointer());
        if (drag->moved) {
          double noteLeft = Canvas::GetLeft(container) + kLeftMargin;
          double noteTop  = Canvas::GetTop (container) + kTopMargin;
          double xPct = m_textNotesContentWidth  > 0 ? noteLeft / m_textNotesContentWidth  * 100.0 : 0.0;
          double yPct = m_textNotesContentHeight > 0 ? noteTop  / m_textNotesContentHeight * 100.0 : 0.0;
          double wPct = m_textNotesContentWidth  > 0 ? (noteBorder.Width()  - 6 - bs2) / m_textNotesContentWidth  * 100.0 : 0.0;
          double hPct = m_textNotesContentHeight > 0 ? (noteBorder.Height() - 6 - bs2) / m_textNotesContentHeight * 100.0 : 0.0;
          std::string msg = "noteMoved|" + uid + "|" + std::to_string(xPct) + "|" +
                            std::to_string(yPct) + "|" + std::to_string(wPct) + "|" +
                            std::to_string(hPct);
          m_reactContext.DispatchEvent(*this, L"topChange",
            [msg](winrt::Microsoft::ReactNative::IJSValueWriter const& w) noexcept {
              w.WriteObjectBegin();
              WriteProperty(w, L"message", winrt::to_hstring(msg));
              w.WriteObjectEnd();
            });
        } else {
          // Tap: activate selection handles + open text editor
          for (auto& [u, setter] : m_textNoteEditModeSetters)  setter(false);
          for (auto& [u, setter] : m_textNoteTextEditSetters)  setter(false);
          m_textNoteEditModeSetters[uid](true);
          m_textNoteTextEditSetters[uid](true);
          m_activeTextNoteUid = uid;
        }
        e.Handled(true);
      });

      // Prevent tap from bubbling up to PagesContainer_Tapped
      container.Tapped([](winrt::Windows::Foundation::IInspectable const&, winrt::Windows::UI::Xaml::Input::TappedRoutedEventArgs const& e) {
        e.Handled(true);
      });

      container.PointerCaptureLost([drag](winrt::Windows::Foundation::IInspectable const&, winrt::Windows::UI::Xaml::Input::PointerRoutedEventArgs const&) mutable {
        drag->dragging = false;
      });

      editBox.LostFocus([this, editBox, uid](winrt::Windows::Foundation::IInspectable const&, winrt::Windows::UI::Xaml::RoutedEventArgs const&) mutable {
        // Signal updated text to React (lines joined by \n)
        std::string text = winrt::to_string(editBox.Text());
        std::string msg  = "textNoteEdited|" + uid + "|" + text;
        m_reactContext.DispatchEvent(*this, L"topChange",
          [msg](winrt::Microsoft::ReactNative::IJSValueWriter const& w) noexcept {
            w.WriteObjectBegin();
            WriteProperty(w, L"message", winrt::to_hstring(msg));
            w.WriteObjectEnd();
          });
        // Deactivate text edit mode; leave selection handles visible
        auto it = m_textNoteTextEditSetters.find(uid);
        if (it != m_textNoteTextEditSetters.end()) it->second(false);
        if (m_activeTextNoteUid == uid) m_activeTextNoteUid.clear();
      });

      textNotesCanvas.Children().Append(container);
      m_textNoteElements[note.uid]  = container;
      m_textNoteInfoCache[note.uid] = note;
    }

    // Restore edit mode for the previously active note (survives prop rebuilds)
    if (!m_activeTextNoteUid.empty()) {
      auto it = m_textNoteEditModeSetters.find(m_activeTextNoteUid);
      if (it != m_textNoteEditModeSetters.end()) {
        it->second(true);
      } else {
        m_activeTextNoteUid.clear(); // note no longer exists
      }
    }
  }

  void RCTPdfControl::SignalNotePress(const std::string& uid, double xPercent, double yPercent) {
    m_reactContext.DispatchEvent(
      *this,
      L"topChange",
      [&](winrt::Microsoft::ReactNative::IJSValueWriter const& eventDataWriter) noexcept {
        eventDataWriter.WriteObjectBegin();
        WriteProperty(eventDataWriter, L"message", winrt::to_hstring(
          "notePressed|" + uid + "|" + std::to_string(xPercent) + "|" + std::to_string(yPercent)
        ));
        eventDataWriter.WriteObjectEnd();
      });
  }

  void RCTPdfControl::SignalNoteMoved(const std::string& uid, double xPercent, double yPercent) {
    m_reactContext.DispatchEvent(
      *this,
      L"topChange",
      [&](winrt::Microsoft::ReactNative::IJSValueWriter const& eventDataWriter) noexcept {
        eventDataWriter.WriteObjectBegin();
        WriteProperty(eventDataWriter, L"message", winrt::to_hstring(
          "noteMoved|" + uid + "|" + std::to_string(xPercent) + "|" + std::to_string(yPercent)
        ));
        eventDataWriter.WriteObjectEnd();
      });
  }

  void RCTPdfControl::SignalHotspotPress(const std::string& uid) {
    m_reactContext.DispatchEvent(
      *this,
      L"topChange",
      [&](winrt::Microsoft::ReactNative::IJSValueWriter const& eventDataWriter) noexcept {
        eventDataWriter.WriteObjectBegin();
        WriteProperty(eventDataWriter, L"message", winrt::to_hstring("hotspotTapped|" + uid));
        eventDataWriter.WriteObjectEnd();
      });
  }
}
