#pragma once

#include <vector>
#include <map>
#include <set>
#include <functional>
#include "winrt/Windows.UI.Xaml.h"
#include "winrt/Windows.UI.Xaml.Markup.h"
#include "winrt/Windows.UI.Xaml.Interop.h"
#include "winrt/Windows.UI.Xaml.Controls.Primitives.h"
#include "winrt/Microsoft.ReactNative.h"
#include "NativeModules.h"
#include "RCTPdfControl.g.h"

namespace winrt::RCTPdf::implementation
{
    struct HotspotInfo {
      double xPos;
      double yPos;
      std::string uid;
      std::string type;
    };

    struct NoteInfo {
      double xPos;
      double yPos;
      std::string uid;
      std::string color;
    };

    struct TextNoteLine {
      std::string text;
      double fontSize    = 14.0;
      std::string fontColor = "#000000";
      double fontOpacity = 1.0;
    };

    struct TextNoteInfo {
      std::string uid;
      double xPos;   // 0..1 (top-left, fraction of content)
      double yPos;   // 0..1
      double width;  // 0..1
      double height; // 0..1
      std::string backgroundColor;
      double backgroundOpacity = 1.0;
      std::string borderColor;
      double borderOpacity = 1.0;
      double borderSize = 0.0;
      std::vector<TextNoteLine> lines; // each element = one user line (Enter-separated)
    };

    struct PDFPageInfo {
      PDFPageInfo(winrt::Windows::UI::Xaml::Controls::Image image, winrt::Windows::Data::Pdf::PdfPage page, double imageScale, double renderScale);
      PDFPageInfo(const PDFPageInfo&);
      PDFPageInfo(PDFPageInfo&&);
      unsigned pageVisiblePixels(bool horizontal, double viewportStart, double viewportEnd) const;
      unsigned pageSize(bool horizontal) const;
      bool needsRender() const;
      winrt::Windows::Foundation::IAsyncAction render();
      winrt::Windows::Foundation::IAsyncAction render(double useScale);
      unsigned height, width;
      unsigned scaledHeight, scaledWidth;
      unsigned scaledTopOffset, scaledLeftOffset;
      double imageScale; // scale at which the image is displayed
      // Multiple tasks can update the image, use the render scale as the sync point
      std::atomic<double> renderScale; // scale at which the image is rendered
      winrt::Windows::UI::Xaml::Controls::Image image;
      winrt::Windows::Data::Pdf::PdfPage page;

      // If zooming-out at what point we rerender the image with smaller scale?
      // E.g. value of 2 means if the image is currently rendered at scale 1.0
      // we will rerender it when the scale is smaller than 0.5
      static constexpr double m_downscaleTreshold = 2;
    };

    struct RCTPdfControl : RCTPdfControlT<RCTPdfControl>
    {
    public:
        RCTPdfControl(Microsoft::ReactNative::IReactContext const& reactContext);

        static winrt::Windows::Foundation::Collections::IMapView<winrt::hstring, winrt::Microsoft::ReactNative::ViewManagerPropertyType> NativeProps() noexcept;
        void UpdateProperties(winrt::Microsoft::ReactNative::IJSValueReader const& propertyMapReader) noexcept;

        static winrt::Microsoft::ReactNative::ConstantProviderDelegate ExportedCustomBubblingEventTypeConstants() noexcept;
        static winrt::Microsoft::ReactNative::ConstantProviderDelegate ExportedCustomDirectEventTypeConstants() noexcept;

        static winrt::Windows::Foundation::Collections::IVectorView<winrt::hstring> Commands() noexcept;
        void DispatchCommand(winrt::hstring const& commandId, winrt::Microsoft::ReactNative::IJSValueReader const& commandArgsReader) noexcept;

        void PagesContainer_PointerWheelChanged(winrt::Windows::Foundation::IInspectable const& sender, winrt::Windows::UI::Xaml::Input::PointerRoutedEventArgs const& e);
        void PagesContainer_PointerMoved(winrt::Windows::Foundation::IInspectable const& sender, winrt::Windows::UI::Xaml::Input::PointerRoutedEventArgs const& e);
        void PagesContainer_PointerPressed(winrt::Windows::Foundation::IInspectable const& sender, winrt::Windows::UI::Xaml::Input::PointerRoutedEventArgs const& e);
        void PagesContainer_PointerReleased(winrt::Windows::Foundation::IInspectable const& sender, winrt::Windows::UI::Xaml::Input::PointerRoutedEventArgs const& e);
        void Pages_SizeChanged(winrt::Windows::Foundation::IInspectable const& sender, winrt::Windows::UI::Xaml::SizeChangedEventArgs const& e);
        winrt::fire_and_forget PagesContainer_ViewChanged(winrt::Windows::Foundation::IInspectable const& sender, winrt::Windows::UI::Xaml::Controls::ScrollViewerViewChangedEventArgs const& e);
        void PagesContainer_Tapped(winrt::Windows::Foundation::IInspectable const& sender, winrt::Windows::UI::Xaml::Input::TappedRoutedEventArgs const& e);
        void PagesContainer_DoubleTapped(winrt::Windows::Foundation::IInspectable const& sender, winrt::Windows::UI::Xaml::Input::DoubleTappedRoutedEventArgs const& e);
        void UpdateHotspots();
        void SignalHotspotPress(const std::string& uid);
        void UpdateNotes();
        void SignalNoteMoved(const std::string& uid, double xPercent, double yPercent);
        void SignalNotePress(const std::string& uid, double xPercent, double yPercent);
        void UpdateTextNotes();
    private:
        Microsoft::ReactNative::IReactContext m_reactContext{ nullptr };

        // Global lock to access the data stuff
        // the pages are rendered in an async way
        std::shared_mutex m_rwlock;
        // URI and password of the PDF
        std::string m_pdfURI;
        std::string m_pdfPassword;
        // Current active page
        int m_currentPage = 0;
        // Margins of each page
        int m_margins = 0;
        // Scale at which the PDF is displayed
        double m_scale = 1;
        double m_minScale = 1;
        double m_maxScale = 3.0;
        // Are we in "horizontal" mode?
        bool m_horizontal = false;
        // Render the pages in reverse order
        bool m_reverse = false;
        // Is in "enablePaging" mode
        bool m_enablePaging = false;

        double offset_X = 0;
        double offset_Y = 0;
        
        double drag_X = 0;
        double drag_Y = 0;
        // When we rescale or change the margins, we can jump to the new position in the view
        // only after the ScrollViewer has updated. We store the target offsets here, and go
        // to them when the control finishes updating;
        std::optional<double> m_targetHorizontalOffset;
        std::optional<double> m_targetVerticalOffset;
        // It is possible, that the new position is reachable even before the control is updated.
        // A helper function that either schedules a change in the view or jumps right to
        // the position
        void ChangeScroll(double targetHorizontalOffset, double targetVerticalOffset);

        // Pages info
        std::vector<PDFPageInfo> m_pages;

        void UpdatePagesInfoMarginOrScale();
        winrt::fire_and_forget LoadPDF(/*std::unique_lock<std::shared_mutex> lock, */ int fitPolicy, bool singlePage);
        void GoToPage(int page);
        winrt::fire_and_forget Rescale(double newScale, double newMargin, bool goToNewPosition);
        void SetOrientation(bool horizontal);
        winrt::Windows::Foundation::IAsyncAction RenderVisiblePages(int page);
        void SignalError(const std::string& error);
        void SignalLoadComplete(int totalPages, int width, int height);
        void SignalPageChange(int page, int totalPages);
        void SignalScaleChanged(double scale, double offsetX, double offsetY);
        void SignalPageTapped(int page, int x, int y);

        // Hotspots
        std::vector<HotspotInfo> m_hotspots;
        static constexpr double m_hotspotSize = 40.0;

        // Notes
        std::vector<NoteInfo> m_notes;
        static constexpr double m_noteSize = 22;
        std::map<std::string, winrt::Windows::UI::Xaml::Controls::Image> m_noteImages;
        std::map<std::string, NoteInfo> m_noteInfoCache;
        double m_notesContentWidth  = 0;
        double m_notesContentHeight = 0;

        // Text Notes
        std::vector<TextNoteInfo> m_textNotes;
        std::map<std::string, winrt::Windows::UI::Xaml::Controls::Canvas> m_textNoteElements;
        std::map<std::string, TextNoteInfo> m_textNoteInfoCache;
        std::map<std::string, std::function<void(bool)>> m_textNoteEditModeSetters;
        std::map<std::string, std::function<void(bool)>> m_textNoteTextEditSetters;
        std::string m_activeTextNoteUid;
        double m_textNotesContentWidth  = 0;
        double m_textNotesContentHeight = 0;

        // Zoom in/out scale multiplier
        static constexpr double m_zoomMultiplier = 1;
        static constexpr double m_defaultMaxZoom = 3.0;
        static constexpr double m_defaultMinZoom = 1.0;
        static constexpr double m_defualtZoom = 1.0;
        static constexpr int m_defaultMargins = 0;
        static constexpr double m_previewZoom = 0.5;
    };
}

namespace winrt::RCTPdf::factory_implementation {
    struct RCTPdfControl : RCTPdfControlT<RCTPdfControl, implementation::RCTPdfControl> {
    };
}
