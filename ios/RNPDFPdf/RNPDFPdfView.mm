/**
 * Copyright (c) 2017-present, Wonday (@wonday.org)
 * All rights reserved.
 *
 * This source code is licensed under the MIT-style license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "RNPDFPdfView.h"

#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreText/CoreText.h>
#import <PDFKit/PDFKit.h>
#import <objc/runtime.h>

#if __has_include(<React/RCTAssert.h>)
#import <React/RCTBridgeModule.h>
#import <React/RCTEventDispatcher.h>
#import <React/UIView+React.h>
#import <React/RCTLog.h>
#import <React/RCTBlobManager.h>
#else
#import "RCTBridgeModule.h"
#import "RCTEventDispatcher.h"
#import "UIView+React.h"
#import "RCTLog.h"
#import <RCTBlobManager.h">
#endif

#ifdef RCT_NEW_ARCH_ENABLED
#import <React/RCTConversions.h>
#import <React/RCTFabricComponentsPlugins.h>
#import <react/renderer/components/rnpdf/ComponentDescriptors.h>
#import <react/renderer/components/rnpdf/Props.h>
#import <react/renderer/components/rnpdf/RCTComponentViewHelpers.h>

// Some RN private method hacking below similar to how it is done in RNScreens:
// https://github.com/software-mansion/react-native-screens/blob/90e548739f35b5ded2524a9d6410033fc233f586/ios/RNSScreenStackHeaderConfig.mm#L30
@interface RCTBridge (Private)
+ (RCTBridge *)currentBridge;
@end

#endif

#ifndef __OPTIMIZE__
// only output log when debug
#define DLog( s, ... ) NSLog( @"<%p %@:(%d)> %@", self, [[NSString stringWithUTF8String:__FILE__] lastPathComponent], __LINE__, [NSString stringWithFormat:(s), ##__VA_ARGS__] )
#else
#define DLog( s, ... )
#endif

// output log both debug and release
#define RLog( s, ... ) NSLog( @"<%p %@:(%d)> %@", self, [[NSString stringWithUTF8String:__FILE__] lastPathComponent], __LINE__, [NSString stringWithFormat:(s), ##__VA_ARGS__] )

const float MAX_SCALE = 3.0f;
const float MIN_SCALE = 1.0f;

@interface RNPDFPdfView() <PDFDocumentDelegate, PDFViewDelegate, UITextViewDelegate
#ifdef RCT_NEW_ARCH_ENABLED
, RCTRNPDFPdfViewViewProtocol
#endif
>
@end

@implementation RNPDFPdfView
{
    RCTBridge *_bridge;
    PDFDocument *_pdfDocument;
    PDFView *_pdfView;
    PDFOutline *root;
    float _fixScaleFactor;
    bool _initialed;
    bool _loadComplete;
    NSArray<NSString *> *_changedProps;
    UITapGestureRecognizer *_doubleTapRecognizer;
    UITapGestureRecognizer *_singleTapRecognizer;
    UIPinchGestureRecognizer *_pinchRecognizer;
    UILongPressGestureRecognizer *_longPressRecognizer;
    UITapGestureRecognizer *_doubleTapEmptyRecognizer;
    UISwipeGestureRecognizer *_swipeLeftRecognizer;
    UISwipeGestureRecognizer *_swipeRightRecognizer;
    NSString *_clickedTextNoteId; // ID da nota de texto clicada (tag 3000)
}

#ifdef RCT_NEW_ARCH_ENABLED

using namespace facebook::react;

+ (ComponentDescriptorProvider)componentDescriptorProvider
{
  return concreteComponentDescriptorProvider<RNPDFPdfViewComponentDescriptor>();
}

// Needed because of this: https://github.com/facebook/react-native/pull/37274
+ (void)load
{
  [super load];
}

- (instancetype)initWithFrame:(CGRect)frame
{
    if (self = [super initWithFrame:frame]) {
        static const auto defaultProps = std::make_shared<const RNPDFPdfViewProps>();
        _props = defaultProps;
        [self initCommonProps];
    }
    return self;
}

- (void)updateProps:(Props::Shared const &)props oldProps:(Props::Shared const &)oldProps
{
    const auto &newProps = *std::static_pointer_cast<const RNPDFPdfViewProps>(props);
    if(!_loadComplete) {
        NSMutableArray<NSString *> *updatedPropNames = [NSMutableArray new];
        if (_path != RCTNSStringFromStringNilIfEmpty(newProps.path)) {
            _path = RCTNSStringFromStringNilIfEmpty(newProps.path);
            [updatedPropNames addObject:@"path"];
        }
        if (_page != newProps.page) {
            _page = newProps.page;
            [updatedPropNames addObject:@"page"];
        }
        if (_scale != newProps.scale) {
            _scale = newProps.scale;
            _manualScale = newProps.scale;
            [updatedPropNames addObject:@"scale"];
        }
        if (_minScale != newProps.minScale) {
            _minScale = newProps.minScale;
            [updatedPropNames addObject:@"minScale"];
        }
        if (_maxScale != newProps.maxScale) {
            _maxScale = newProps.maxScale;
            [updatedPropNames addObject:@"maxScale"];
        }
        if (_horizontal != newProps.horizontal) {
            _horizontal = newProps.horizontal;
            [updatedPropNames addObject:@"horizontal"];
        }
        if (_enablePaging != newProps.enablePaging) {
            _enablePaging = newProps.enablePaging;
            [updatedPropNames addObject:@"enablePaging"];
        }
        if (_enableRTL != newProps.enableRTL) {
            _enableRTL = newProps.enableRTL;
            [updatedPropNames addObject:@"enableRTL"];
        }
        if (_enableAnnotationRendering != newProps.enableAnnotationRendering) {
            _enableAnnotationRendering = newProps.enableAnnotationRendering;
            [updatedPropNames addObject:@"enableAnnotationRendering"];
        }
        if (_enableDoubleTapZoom != newProps.enableDoubleTapZoom) {
            _enableDoubleTapZoom = newProps.enableDoubleTapZoom;
            [updatedPropNames addObject:@"enableDoubleTapZoom"];
        }
        if (_fitPolicy != newProps.fitPolicy) {
            _fitPolicy = newProps.fitPolicy;
            [updatedPropNames addObject:@"fitPolicy"];
        }
        if (_spacing != newProps.spacing) {
            _spacing = newProps.spacing;
            [updatedPropNames addObject:@"spacing"];
        }
        if (_password != RCTNSStringFromStringNilIfEmpty(newProps.password)) {
            _password = RCTNSStringFromStringNilIfEmpty(newProps.password);
            [updatedPropNames addObject:@"password"];
        }
        if (_singlePage != newProps.singlePage) {
            _singlePage = newProps.singlePage;
            [updatedPropNames addObject:@"singlePage"];
        }
        if (_showsHorizontalScrollIndicator != newProps.showsHorizontalScrollIndicator) {
            _showsHorizontalScrollIndicator = newProps.showsHorizontalScrollIndicator;
            [updatedPropNames addObject:@"showsHorizontalScrollIndicator"];
        }
        if (_showsVerticalScrollIndicator != newProps.showsVerticalScrollIndicator) {
            _showsVerticalScrollIndicator = newProps.showsVerticalScrollIndicator;
            [updatedPropNames addObject:@"showsVerticalScrollIndicator"];
        }
        
        if (_scrollEnabled != newProps.scrollEnabled) {
            _scrollEnabled = newProps.scrollEnabled;
            [updatedPropNames addObject:@"scrollEnabled"];
        }
        
        if (_hotspots != RCTNSStringFromStringNilIfEmpty(newProps.hotspots)) {
            _hotspots = RCTNSStringFromStringNilIfEmpty(newProps.hotspots);
        }
        
        if (_notes != RCTNSStringFromStringNilIfEmpty(newProps.notes)) {
            _notes = RCTNSStringFromStringNilIfEmpty(newProps.notes);
        }
        
        if (_textNotes != RCTNSStringFromStringNilIfEmpty(newProps.textNotes)) {
            _textNotes = RCTNSStringFromStringNilIfEmpty(newProps.textNotes);
        }
        [self didSetProps:updatedPropNames];
        [super updateProps:props oldProps:oldProps];
    }
    else {
        // Usar epsilon para comparar floats e evitar problemas de precisão
        const CGFloat epsilon = 0.001;
        if (fabs(_manualScale - newProps.scale) > epsilon) {
            _pdfView.scaleFactor = _pdfView.scaleFactor = newProps.scale * _fixScaleFactor;
            _scale = newProps.scale;
            _manualScale = newProps.scale;
        }
        if (![_hotspots isEqualToString:RCTNSStringFromStringNilIfEmpty(newProps.hotspots)]) {
            _hotspots = RCTNSStringFromStringNilIfEmpty(newProps.hotspots);
            [self drawHotspots];
        }
        if (![_notes isEqualToString:RCTNSStringFromStringNilIfEmpty(newProps.notes)]) {
            _notes = RCTNSStringFromStringNilIfEmpty(newProps.notes);
            [self drawNotes];
        }
        if (![_textNotes isEqualToString:RCTNSStringFromStringNilIfEmpty(newProps.textNotes)]) {
            _textNotes = RCTNSStringFromStringNilIfEmpty(newProps.textNotes);
            [self drawTextNotes];
        }
    }
}

// already added in case https://github.com/facebook/react-native/pull/35378 has been merged
- (BOOL)shouldBeRecycled
{
    return NO;
}

- (void)prepareForRecycle
{
    [super prepareForRecycle];

    [_pdfView removeFromSuperview];
    _pdfDocument = Nil;
    _pdfView = Nil;
    //Remove notifications
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"PDFViewDocumentChangedNotification" object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"PDFViewPageChangedNotification" object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"PDFViewScaleChangedNotification" object:nil];

    // remove old recognizers before adding new ones
    [self removeGestureRecognizer:_doubleTapRecognizer];
    [self removeGestureRecognizer:_singleTapRecognizer];
    [self removeGestureRecognizer:_pinchRecognizer];
    [self removeGestureRecognizer:_longPressRecognizer];
    [self removeGestureRecognizer:_doubleTapEmptyRecognizer];
    [self removeGestureRecognizer:_swipeLeftRecognizer];
    [self removeGestureRecognizer:_swipeRightRecognizer];

    [self initCommonProps];
}

- (void)updateLayoutMetrics:(const facebook::react::LayoutMetrics &)layoutMetrics oldLayoutMetrics:(const facebook::react::LayoutMetrics &)oldLayoutMetrics
{
    // Fabric equivalent of `reactSetFrame` method
    [super updateLayoutMetrics:layoutMetrics oldLayoutMetrics:oldLayoutMetrics];
    _pdfView.frame = CGRectMake(0, 0, layoutMetrics.frame.size.width, layoutMetrics.frame.size.height);

    NSMutableArray *mProps = [_changedProps mutableCopy];
    if (_initialed) {
        [mProps removeObject:@"path"];
    }
    _initialed = YES;

    [self didSetProps:mProps];
}

- (void)handleCommand:(const NSString *)commandName args:(const NSArray *)args
{
  RCTRNPDFPdfViewHandleCommand(self, commandName, args);
}

- (void)setNativePage:(NSInteger)page
{
    _page = page;
    [self didSetProps:[NSArray arrayWithObject:@"page"]];
}

#endif

- (instancetype)initWithBridge:(RCTBridge *)bridge
{
    self = [super init];
    if (self) {
        _bridge = bridge;
        [self initCommonProps];
    }

    return self;
}

- (void)initCommonProps
{
    _page = 1;
    _scale = 1;
    _minScale = MIN_SCALE;
    _maxScale = MAX_SCALE;
    _horizontal = NO;
    _enablePaging = NO;
    _enableRTL = NO;
    _enableAnnotationRendering = YES;
    _enableDoubleTapZoom = YES;
    _fitPolicy = 2;
    _spacing = 10;
    _singlePage = NO;
    _showsHorizontalScrollIndicator = YES;
    _showsVerticalScrollIndicator = YES;
    _scrollEnabled = YES;
    _hotspots = nil;
    _notes = nil;

    // init and config PDFView
    _pdfView = [[PDFView alloc] initWithFrame:CGRectMake(0, 0, 500, 500)];
    _pdfView.displayMode = kPDFDisplaySinglePageContinuous;
    _pdfView.autoScales = YES;
    _pdfView.displaysPageBreaks = YES;
    _pdfView.displayBox = kPDFDisplayBoxCropBox;
    _pdfView.backgroundColor = [UIColor clearColor];

    _fixScaleFactor = -1.0f;
    _initialed = NO;
    _loadComplete = NO;
    _changedProps = NULL;

    [self addSubview:_pdfView];


    // register notification
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(onDocumentChanged:) name:PDFViewDocumentChangedNotification object:_pdfView];
    [center addObserver:self selector:@selector(onPageChanged:) name:PDFViewPageChangedNotification object:_pdfView];
    [center addObserver:self selector:@selector(onScaleChanged:) name:PDFViewScaleChangedNotification object:_pdfView];
    

    [[_pdfView document] setDelegate: self];
    [_pdfView setDelegate: self];
    
    
    // Disable built-in double tap, so as not to conflict with custom recognizers.
    for (UIGestureRecognizer *recognizer in _pdfView.gestureRecognizers) {
        if ([recognizer isKindOfClass:[UITapGestureRecognizer class]]) {
            UITapGestureRecognizer *tap = (UITapGestureRecognizer *)recognizer;
            if (tap.numberOfTapsRequired == 2) {
                recognizer.enabled = NO;
            }
        }
    }

    [self bindTap];
}


- (void)PDFViewWillClickOnLink:(PDFView *)sender withURL:(NSURL *)url
{
    NSString *_url = url.absoluteString;
    [self notifyOnChangeWithMessage:
                     [[NSString alloc] initWithString:
                      [NSString stringWithFormat:
                       @"linkPressed|%s", _url.UTF8String]]];
}

- (void)didSetProps:(NSArray<NSString *> *)changedProps
{
    if (!_initialed) {

        _changedProps = changedProps;

    } else {

        if ([changedProps containsObject:@"path"]) {


            if (_pdfDocument != Nil) {
                //Release old doc
                _pdfDocument = Nil;
            }
            
            if ([_path hasPrefix:@"blob:"]) {
                RCTBlobManager *blobManager = [
#ifdef RCT_NEW_ARCH_ENABLED
        [RCTBridge currentBridge]
#else
        _bridge
#endif // RCT_NEW_ARCH_ENABLED
                    moduleForName:@"BlobModule"];
                NSURL *blobURL = [NSURL URLWithString:_path];
                NSData *blobData = [blobManager resolveURL:blobURL];
                if (blobData != nil) {
                    _pdfDocument = [[PDFDocument alloc] initWithData:blobData];
                }
            } else {
            
                // decode file path
                _path = (__bridge_transfer NSString *)CFURLCreateStringByReplacingPercentEscapes(NULL, (CFStringRef)_path, CFSTR(""));
                NSURL *fileURL = [NSURL fileURLWithPath:_path];
                _pdfDocument = [[PDFDocument alloc] initWithURL:fileURL];
            }

            if (_pdfDocument) {

                //check need password or not
                if (_pdfDocument.isLocked && ![_pdfDocument unlockWithPassword:_password]) {

                    [self notifyOnChangeWithMessage:@"error|Password required or incorrect password."];

                    _pdfDocument = Nil;
                    return;
                }

                _pdfView.document = _pdfDocument;
            } else {

                [self notifyOnChangeWithMessage:[[NSString alloc] initWithString:[NSString stringWithFormat:@"error|Load pdf failed. path=%s",_path.UTF8String]]];

                _pdfDocument = Nil;
                return;
            }
        }

        if (_pdfDocument && ([changedProps containsObject:@"path"] || [changedProps containsObject:@"spacing"])) {
            if (_horizontal) {
                _pdfView.pageBreakMargins = UIEdgeInsetsMake(0,_spacing,0,0);
                if (_spacing==0) {
                    if (@available(iOS 12.0, *)) {
                        _pdfView.pageShadowsEnabled = NO;
                    }
                } else {
                    if (@available(iOS 12.0, *)) {
                        _pdfView.pageShadowsEnabled = YES;
                    }
                }
            } else {
                _pdfView.pageBreakMargins = UIEdgeInsetsMake(0,0,_spacing,0);
                if (_spacing==0) {
                    if (@available(iOS 12.0, *)) {
                        _pdfView.pageShadowsEnabled = NO;
                    }
                } else {
                    if (@available(iOS 12.0, *)) {
                        _pdfView.pageShadowsEnabled = YES;
                    }
                }
            }
        }

        if (_pdfDocument && ([changedProps containsObject:@"path"] || [changedProps containsObject:@"enableRTL"])) {
            _pdfView.displaysRTL = _enableRTL;
        }

        if (_pdfDocument && ([changedProps containsObject:@"path"] || [changedProps containsObject:@"enableAnnotationRendering"])) {
            if (!_enableAnnotationRendering) {
                for (unsigned long i=0; i<_pdfView.document.pageCount; i++) {
                    PDFPage *pdfPage = [_pdfView.document pageAtIndex:i];
                    for (unsigned long j=0; j<pdfPage.annotations.count; j++) {
                        pdfPage.annotations[j].shouldDisplay = _enableAnnotationRendering;
                    }
                }
            }
        }

        if (_pdfDocument && ([changedProps containsObject:@"path"] || [changedProps containsObject:@"fitPolicy"] || [changedProps containsObject:@"minScale"] || [changedProps containsObject:@"maxScale"])) {

            PDFPage *pdfPage = _pdfView.currentPage ? _pdfView.currentPage : [_pdfDocument pageAtIndex:_pdfDocument.pageCount-1];
            CGRect pdfPageRect = [pdfPage boundsForBox:kPDFDisplayBoxCropBox];

            // some pdf with rotation, then adjust it
            if (pdfPage.rotation == 90 || pdfPage.rotation == 270) {
                pdfPageRect = CGRectMake(0, 0, pdfPageRect.size.height, pdfPageRect.size.width);
            }

            if (_fitPolicy == 0) {
                _fixScaleFactor = self.frame.size.width/pdfPageRect.size.width;
                _pdfView.scaleFactor = _scale * _fixScaleFactor;
                _pdfView.minScaleFactor = _fixScaleFactor*_minScale;
                _pdfView.maxScaleFactor = _fixScaleFactor*_maxScale;
            } else if (_fitPolicy == 1) {
                _fixScaleFactor = self.frame.size.height/pdfPageRect.size.height;
                _pdfView.scaleFactor = _scale * _fixScaleFactor;
                _pdfView.minScaleFactor = _fixScaleFactor*_minScale;
                _pdfView.maxScaleFactor = _fixScaleFactor*_maxScale;
            } else {
                float pageAspect = pdfPageRect.size.width/pdfPageRect.size.height;
                float reactViewAspect = self.frame.size.width/self.frame.size.height;
                if (reactViewAspect>pageAspect) {
                    _fixScaleFactor = self.frame.size.height/pdfPageRect.size.height;
                    _pdfView.scaleFactor = _scale * _fixScaleFactor;
                    _pdfView.minScaleFactor = _fixScaleFactor*_minScale;
                    _pdfView.maxScaleFactor = _fixScaleFactor*_maxScale;
                } else {
                    _fixScaleFactor = self.frame.size.width/pdfPageRect.size.width;
                    _pdfView.scaleFactor = _scale * _fixScaleFactor;
                    _pdfView.minScaleFactor = _fixScaleFactor*_minScale;
                    _pdfView.maxScaleFactor = _fixScaleFactor*_maxScale;
                }
            }

        }

        if (_pdfDocument && ([changedProps containsObject:@"path"] || [changedProps containsObject:@"scale"])) {
            _pdfView.scaleFactor = _scale * _fixScaleFactor;
            if (_pdfView.scaleFactor>_pdfView.maxScaleFactor) _pdfView.scaleFactor = _pdfView.maxScaleFactor;
            if (_pdfView.scaleFactor<_pdfView.minScaleFactor) _pdfView.scaleFactor = _pdfView.minScaleFactor;
        }

        if (_pdfDocument && ([changedProps containsObject:@"path"] || [changedProps containsObject:@"horizontal"])) {
            if (_horizontal) {
                _pdfView.displayDirection = kPDFDisplayDirectionHorizontal;
                _pdfView.pageBreakMargins = UIEdgeInsetsMake(0,_spacing,0,0);
            } else {
                _pdfView.displayDirection = kPDFDisplayDirectionVertical;
                _pdfView.pageBreakMargins = UIEdgeInsetsMake(0,0,_spacing,0);
            }
        }

        if (_pdfDocument && ([changedProps containsObject:@"path"] || [changedProps containsObject:@"enablePaging"])) {
            if (_enablePaging) {
                [_pdfView usePageViewController:YES withViewOptions:@{UIPageViewControllerOptionSpineLocationKey:@(UIPageViewControllerSpineLocationMin),UIPageViewControllerOptionInterPageSpacingKey:@(_spacing)}];
            } else {
                [_pdfView usePageViewController:NO withViewOptions:Nil];
            }
        }

        if (_pdfDocument && ([changedProps containsObject:@"path"] || [changedProps containsObject:@"singlePage"])) {
            if (_singlePage) {
                _pdfView.displayMode = kPDFDisplaySinglePage;
                _pdfView.userInteractionEnabled = NO;
            } else {
                _pdfView.displayMode = kPDFDisplaySinglePageContinuous;
                _pdfView.userInteractionEnabled = YES;
            }
        }

        if (_pdfDocument && ([changedProps containsObject:@"path"] || [changedProps containsObject:@"showsHorizontalScrollIndicator"] || [changedProps containsObject:@"showsVerticalScrollIndicator"])) {
            [self setScrollIndicators:self horizontal:_showsHorizontalScrollIndicator vertical:_showsVerticalScrollIndicator depth:0];
        }

        if (_pdfDocument && ([changedProps containsObject:@"path"] || [changedProps containsObject:@"scrollEnabled"])) {
            if (_scrollEnabled) {
                for (UIView *subview in _pdfView.subviews) {
                    if ([subview isKindOfClass:[UIScrollView class]]) {
                        UIScrollView *scrollView = (UIScrollView *)subview;
                        scrollView.scrollEnabled = YES;
                    }
                }
            } else {
                for (UIView *subview in _pdfView.subviews) {
                    if ([subview isKindOfClass:[UIScrollView class]]) {
                        UIScrollView *scrollView = (UIScrollView *)subview;
                        scrollView.scrollEnabled = NO;
                    }
                }
            }
        }

        if (_pdfDocument && ([changedProps containsObject:@"path"] || [changedProps containsObject:@"enablePaging"] || [changedProps containsObject:@"horizontal"] || [changedProps containsObject:@"page"])) {

            PDFPage *pdfPage = [_pdfDocument pageAtIndex:_page-1];
            if (pdfPage && _page == 1) {
                // goToDestination() would be better. However, there is an
                // error in the pointLeftTop computation that often results in
                // scrolling to the middle of the page.
                // Special case workaround to make starting at the first page
                // align acceptably.
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self->_pdfView goToRect:CGRectMake(0, NSUIntegerMax, 1, 1) onPage:pdfPage];
                });
            } else if (pdfPage) {
                CGRect pdfPageRect = [pdfPage boundsForBox:kPDFDisplayBoxCropBox];

                // some pdf with rotation, then adjust it
                if (pdfPage.rotation == 90 || pdfPage.rotation == 270) {
                    pdfPageRect = CGRectMake(0, 0, pdfPageRect.size.height, pdfPageRect.size.width);
                }

                CGPoint pointLeftTop = CGPointMake(0, pdfPageRect.size.height);
                PDFDestination *pdfDest = [[PDFDestination alloc] initWithPage:pdfPage atPoint:pointLeftTop];
                [_pdfView goToDestination:pdfDest];
                _pdfView.scaleFactor = _fixScaleFactor*_scale;
            }
        }

        _pdfView.backgroundColor = [UIColor clearColor];
        [_pdfView layoutDocumentView];
        [self setNeedsDisplay];
    }
}


- (void)reactSetFrame:(CGRect)frame
{
    [super reactSetFrame:frame];
    _pdfView.frame = CGRectMake(0, 0, frame.size.width, frame.size.height);

    NSMutableArray *mProps = [_changedProps mutableCopy];
    if (_initialed) {
        [mProps removeObject:@"path"];
    }
    _initialed = YES;

    [self didSetProps:mProps];
}


- (void)notifyOnChangeWithMessage:(NSString *)message
{
#ifdef RCT_NEW_ARCH_ENABLED
    if (_eventEmitter != nullptr) {
             std::dynamic_pointer_cast<const RNPDFPdfViewEventEmitter>(_eventEmitter)
                 ->onChange(RNPDFPdfViewEventEmitter::OnChange{.message = RCTStringFromNSString(message)});
           }
#else
    _onChange(@{ @"message": message});
#endif
}

- (void)dealloc{

    _pdfDocument = Nil;
    _pdfView = Nil;

    //Remove notifications
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"PDFViewDocumentChangedNotification" object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"PDFViewPageChangedNotification" object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"PDFViewScaleChangedNotification" object:nil];

    _doubleTapRecognizer = nil;
    _singleTapRecognizer = nil;
    _pinchRecognizer = nil;
    _longPressRecognizer = nil;
    _doubleTapEmptyRecognizer = nil;
    _swipeLeftRecognizer = nil;
    _swipeRightRecognizer = nil;
}

#pragma mark notification process
- (void)onDocumentChanged:(NSNotification *)noti
{
    if (_pdfDocument) {

        unsigned long numberOfPages = _pdfDocument.pageCount;
        PDFPage *page = [_pdfDocument pageAtIndex:_pdfDocument.pageCount-1];
        CGSize pageSize = [_pdfView rowSizeForPage:page];
        NSString *jsonString = [self getTableContents];

        _loadComplete = YES;
        [self notifyOnChangeWithMessage:[[NSString alloc] initWithString:[NSString stringWithFormat:@"loadComplete|%lu|%f|%f|%@", numberOfPages, pageSize.width, pageSize.height,jsonString]]];
        [self addOverlaysToPDF];
    }

}


-(NSString *) getTableContents
{

    NSMutableArray<PDFOutline *> *arrTableOfContents = [[NSMutableArray alloc] init];

    if (_pdfDocument.outlineRoot) {

        PDFOutline *currentRoot = _pdfDocument.outlineRoot;
        NSMutableArray<PDFOutline *> *stack = [[NSMutableArray alloc] init];

        [stack addObject:currentRoot];

        while (stack.count > 0) {

            PDFOutline *currentOutline = stack.lastObject;
            [stack removeLastObject];

            if (currentOutline.label.length > 0){
                [arrTableOfContents addObject:currentOutline];
            }

            for ( NSInteger i= currentOutline.numberOfChildren; i > 0; i-- )
            {
                [stack addObject:[currentOutline childAtIndex:i-1]];
            }
        }
    }

    NSMutableArray *arrParentsContents = [[NSMutableArray alloc] init];

    for ( NSInteger i= 0; i < arrTableOfContents.count; i++ )
    {
        PDFOutline *currentOutline = [arrTableOfContents objectAtIndex:i];

        NSInteger indentationLevel = -1;

        PDFOutline *parentOutline = currentOutline.parent;

        while (parentOutline != nil) {
            indentationLevel += 1;
            parentOutline = parentOutline.parent;
        }

        if (indentationLevel == 0) {

            NSMutableDictionary *DXParentsContent = [[NSMutableDictionary alloc] init];

            [DXParentsContent setObject:[[NSMutableArray alloc] init] forKey:@"children"];
            [DXParentsContent setObject:@"" forKey:@"mNativePtr"];
            [DXParentsContent setObject:[NSString stringWithFormat:@"%lu", [_pdfDocument indexForPage:currentOutline.destination.page]] forKey:@"pageIdx"];
            [DXParentsContent setObject:currentOutline.label forKey:@"title"];

            //currentOutlin
            //mNativePtr
            [arrParentsContents addObject:DXParentsContent];
        }
        else {
            NSMutableDictionary *DXParentsContent = [arrParentsContents lastObject];

            NSMutableArray *arrChildren = [DXParentsContent valueForKey:@"children"];

            while (indentationLevel > 1) {
                NSMutableDictionary *DXchild = [arrChildren lastObject];
                arrChildren = [DXchild valueForKey:@"children"];
                indentationLevel--;
            }

            NSMutableDictionary *DXChildContent = [[NSMutableDictionary alloc] init];
            [DXChildContent setObject:[[NSMutableArray alloc] init] forKey:@"children"];
            [DXChildContent setObject:@"" forKey:@"mNativePtr"];
            [DXChildContent setObject:[NSString stringWithFormat:@"%lu", [_pdfDocument indexForPage:currentOutline.destination.page]] forKey:@"pageIdx"];
            [DXChildContent setObject:currentOutline.label forKey:@"title"];
            [arrChildren addObject:DXChildContent];

        }
    }

    NSError *error;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:arrParentsContents options:NSJSONWritingPrettyPrinted error:&error];

    NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];

    return jsonString;

}

- (void)onPageChanged:(NSNotification *)noti
{

    if (_pdfDocument) {
        PDFPage *currentPage = _pdfView.currentPage;
        unsigned long page = [_pdfDocument indexForPage:currentPage];
        unsigned long numberOfPages = _pdfDocument.pageCount;

        [self notifyOnChangeWithMessage:[[NSString alloc] initWithString:[NSString stringWithFormat:@"pageChanged|%lu|%lu", page+1, numberOfPages]]];
    }
}

- (void)onScaleChanged:(NSNotification *)notification
{
    if (_initialed && _fixScaleFactor>0) {
        if (_scale != _pdfView.scaleFactor/_fixScaleFactor) {
            _scale = _pdfView.scaleFactor/_fixScaleFactor;
            [self drawNotes];
            [self adjustTextNotesBorderWidth];
            [self notifyOnChangeWithMessage:[[NSString alloc] initWithString:[NSString stringWithFormat:@"scaleChanged|%f", _scale]]];
        }
    }

}

#pragma mark gesture process

/**
 *  Empty double tap handler
 *
 *
 */
- (void)handleDoubleTapEmpty:(UITapGestureRecognizer *)recognizer {}

/**
 *  Tap
 *  zoom reset or zoom in
 *
 *  @param recognizer
 */
- (void)handleDoubleTap:(UITapGestureRecognizer *)recognizer
{

    // Prevent double tap from selecting text.
    dispatch_async(dispatch_get_main_queue(), ^{
        [self->_pdfView clearSelection];
    });

    // Event appears to be consumed; broadcast for JS.
    // _onChange(@{ @"message": @"pageDoubleTap" });

    if (!_enableDoubleTapZoom) {
        return;
    }

    // Cycle through min/mid/max scale factors to be consistent with Android
    float min = self->_pdfView.minScaleFactor/self->_fixScaleFactor;
    float max = self->_pdfView.maxScaleFactor/self->_fixScaleFactor;
    float mid = (max - min) / 2 + min;
    float scale = self->_scale;
    if (self->_scale < mid) {
        scale = mid;
    } else if (self->_scale < max) {
        scale = max;
    } else {
        scale = min;
    }

    CGFloat newScale = scale * self->_fixScaleFactor;
    CGPoint tapPoint = [recognizer locationInView:self->_pdfView];

    PDFPage *tappedPdfPage = [_pdfView pageForPoint:tapPoint nearest:NO];
    PDFPage *pageRef;
    if (tappedPdfPage) {
        pageRef = tappedPdfPage;
    }   else {
        pageRef = self->_pdfView.currentPage;
    }
    tapPoint = [self->_pdfView convertPoint:tapPoint toPage:pageRef];

    CGRect tempZoomRect = CGRectZero;
    tempZoomRect.size.width = self->_pdfView.frame.size.width;
    tempZoomRect.size.height = 1;
    tempZoomRect.origin = tapPoint;

    dispatch_async(dispatch_get_main_queue(), ^{
        [UIView animateWithDuration:0.3 animations:^{
            [self->_pdfView setScaleFactor:newScale];

            [self->_pdfView goToRect:tempZoomRect onPage:pageRef];
            CGPoint defZoomOrigin = [self->_pdfView convertPoint:tempZoomRect.origin fromPage:pageRef];
            defZoomOrigin.x = defZoomOrigin.x - self->_pdfView.frame.size.width / 2;
            defZoomOrigin.y = defZoomOrigin.y - self->_pdfView.frame.size.height / 2;
            defZoomOrigin = [self->_pdfView convertPoint:defZoomOrigin toPage:pageRef];
            CGRect defZoomRect =  CGRectOffset(
                tempZoomRect,
                defZoomOrigin.x - tempZoomRect.origin.x,
                defZoomOrigin.y - tempZoomRect.origin.y
            );
            [self->_pdfView goToRect:defZoomRect onPage:pageRef];

            [self setNeedsDisplay];
            [self onScaleChanged:Nil];
        }];
    });
}

/**
 *  Single Tap
 *  stop zoom
 *
 *  @param recognizer
 */
- (void)handleSingleTap:(UITapGestureRecognizer *)sender
{
    //_pdfView.scaleFactor = _pdfView.minScaleFactor;

    // Fechar qualquer TextField de nota de texto que esteja em edição
    [self dismissAllTextFieldsInView:_pdfView];

    // Esconder controlos de edição e limpar nota clicada
    NSLog(@"hideAllTextNoteEditingControls 1");
    [self hideAllTextNoteEditingControls];
    _clickedTextNoteId = nil;

    NSLog(@"pageSingleTap 0");
    
    CGPoint point = [sender locationInView:self];
    [self notifyOnChangeWithMessage:[[NSString alloc] initWithString:[NSString stringWithFormat:@"pageSingleTap|%lu|%f|%f", 1, point.x, point.y]]];

    //[self setNeedsDisplay];
    //[self onScaleChanged:Nil];


}

// Método auxiliar para fechar todos os TextFields
- (void)dismissAllTextFieldsInView:(UIView *)view
{
    for (UIView *subview in view.subviews) {
        if ([subview isKindOfClass:[UITextField class]] && subview.tag == 3000) {
            UITextField *textField = (UITextField *)subview;
            if ([textField isFirstResponder]) {
                [textField resignFirstResponder];
            }
        }
        // Recursivamente procurar em subviews
        [self dismissAllTextFieldsInView:subview];
    }
}

// Mostrar controlos de edição para uma nota de texto
- (void)showTextNoteEditingControlsForNoteId:(NSString *)noteId
{
    for (UIView *subview in _pdfView.subviews) {
        if ([subview isKindOfClass:[UIScrollView class]]) {
            UIScrollView *scrollView = (UIScrollView *)subview;
            for (UIView *pageView in scrollView.subviews) {
                for (UIView *view in pageView.subviews) {
                    if (view.tag == 3000 && [view.accessibilityIdentifier isEqualToString:noteId]) {
                        // Procurar noteView (tag 3001)
                        UIView *noteView = [view viewWithTag:3001];
                        if (noteView) {
                            // Mostrar e ativar UITextView para edição
                            UITextView *textView = [noteView viewWithTag:3002];
                            if (textView) {
                                textView.hidden = NO;  // MOSTRAR para edição
                                textView.editable = YES;
                                textView.userInteractionEnabled = YES;

                                // Mostrar teclado
                                dispatch_async(dispatch_get_main_queue(), ^{
                                    [textView becomeFirstResponder];
                                });
                            }
                        }

                        // Mostrar controlos de edição (tags 4001-4007, incluindo borda dotted)
                        for (UIView *control in view.subviews) {
                            if (control.tag >= 4001 && control.tag <= 4007) {
                                control.hidden = NO;
                            }
                        }
                        NSLog(@"✅ Controlos de edição e borda dotted mostrados para nota: %@", noteId);
                        return;
                    }
                }
            }
        }
    }
}

// Esconder todos os controlos de edição de notas de texto
- (void)hideAllTextNoteEditingControls
{
    for (UIView *subview in _pdfView.subviews) {
        if ([subview isKindOfClass:[UIScrollView class]]) {
            UIScrollView *scrollView = (UIScrollView *)subview;
            for (UIView *pageView in scrollView.subviews) {
                for (UIView *view in pageView.subviews) {
                    if (view.tag == 3000) {
                        // Esconder controlos de edição (tags 4001-4007, incluindo borda dotted)
                        for (UIView *control in view.subviews) {
                            if (control.tag >= 4001 && control.tag <= 4007) {
                                control.hidden = YES;
                            }
                        }

                        // Remover UITextView se existir
                        UIView *noteView = [view viewWithTag:3001];
                        if (noteView) {
                            UITextView *textView = [noteView viewWithTag:3002];
                            if (textView) {
                                // Fechar teclado
                                [textView resignFirstResponder];

                                // Verificar se o texto mudou comparando com o original
                                NSAttributedString *originalText = objc_getAssociatedObject(textView, "originalText");
                                NSString *newPlainText = textView.text;
                                NSString *originalPlainText = originalText.string;

                                if (![newPlainText isEqualToString:originalPlainText]) {
                                    // Texto mudou - criar novo attributedString com estilo original
                                    NSLog(@"📝 Texto editado - plain text: %@", newPlainText);

                                    // Pegar atributos da primeira linha do texto original
                                    NSDictionary *baseAttributes = [originalText attributesAtIndex:0 effectiveRange:NULL];
                                    NSAttributedString *newAttributedText = [[NSAttributedString alloc] initWithString:newPlainText attributes:baseAttributes];

                                    // Guardar o novo texto editado
                                    objc_setAssociatedObject(noteView, "attributedText", newAttributedText, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

                                    // Atualizar CATextLayer
                                    for (CALayer *sublayer in noteView.layer.sublayers) {
                                        if ([sublayer isKindOfClass:[CATextLayer class]]) {
                                            CATextLayer *textLayer = (CATextLayer *)sublayer;
                                            textLayer.string = newAttributedText;
                                            break;
                                        }
                                    }

                                    // TODO: Notificar JavaScript sobre a mudança de texto
                                }

                                // Remover UITextView
                                [textView removeFromSuperview];
                            }
                        }
                    }
                }
            }
        }
    }
}


-(void)handlePinch:(UIPinchGestureRecognizer *)sender{
    if (sender.state == UIGestureRecognizerStateBegan) {
        
        NSLog(@"hideAllTextNoteEditingControls 2");
        [self hideAllTextNoteEditingControls];
        _clickedTextNoteId = nil;
    }

    if (sender.state == UIGestureRecognizerStateEnded ||
        sender.state == UIGestureRecognizerStateCancelled) {
        // Reabilitar gestures das notas após o pinch terminar
        for (UIView *subview in _pdfView.subviews) {
            if ([subview isKindOfClass:[UIScrollView class]]) {
                UIScrollView *scrollView = (UIScrollView *)subview;
                for (UIView *pageView in scrollView.subviews) {
                    for (UIView *overlay in pageView.subviews) {
                        if (overlay.tag == 1000 || overlay.tag == 2000 || overlay.tag == 3000) {
                            // Reabilitar todos os gesture recognizers da nota
                            for (UIGestureRecognizer *gesture in overlay.gestureRecognizers) {
                                gesture.enabled = YES;
                            }
                        }
                    }
                }
            }
        }
        [self notifyOnChangeWithMessage:[[NSString alloc] initWithString:[NSString stringWithFormat:@"scaleChangedEnd|%f", _scale]]];
    } else {
        // Desabilitar gestures das notas durante todo o pinch
        for (UIView *subview in _pdfView.subviews) {
            if ([subview isKindOfClass:[UIScrollView class]]) {
                UIScrollView *scrollView = (UIScrollView *)subview;
                for (UIView *pageView in scrollView.subviews) {
                    for (UIView *overlay in pageView.subviews) {
                        if (overlay.tag == 1000 || overlay.tag == 2000 || overlay.tag == 3000) {
                            // Desabilitar todos os gesture recognizers da nota
                            for (UIGestureRecognizer *gesture in overlay.gestureRecognizers) {
                                gesture.enabled = NO;
                            }
                        }
                    }
                }
            }
        }
    }

    [self onScaleChanged:Nil];
}

/**
 *  Do nothing on long Press
 *
 *
 */
- (void)handleLongPress:(UILongPressGestureRecognizer *)sender{

}

/**
 *  Bind tap
 *
 *
 */
- (void)bindTap
{
    UITapGestureRecognizer *doubleTapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self
                                                                                          action:@selector(handleDoubleTap:)];
    //trigger by one finger and double touch
    doubleTapRecognizer.numberOfTapsRequired = 2;
    doubleTapRecognizer.numberOfTouchesRequired = 1;
    doubleTapRecognizer.delegate = self;

    [self addGestureRecognizer:doubleTapRecognizer];
    _doubleTapRecognizer = doubleTapRecognizer;

    UITapGestureRecognizer *singleTapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self
                                                                                          action:@selector(handleSingleTap:)];
    //trigger by one finger and one touch
    singleTapRecognizer.numberOfTapsRequired = 1;
    singleTapRecognizer.numberOfTouchesRequired = 1;
    singleTapRecognizer.delegate = self;

    [self addGestureRecognizer:singleTapRecognizer];
    _singleTapRecognizer = singleTapRecognizer;

    [singleTapRecognizer requireGestureRecognizerToFail:doubleTapRecognizer];

    UIPinchGestureRecognizer *pinchRecognizer = [[UIPinchGestureRecognizer alloc] initWithTarget:self
                                                                                          action:@selector(handlePinch:)];
    [self addGestureRecognizer:pinchRecognizer];
    _pinchRecognizer = pinchRecognizer;

    pinchRecognizer.delegate = self;

    UILongPressGestureRecognizer *longPressRecognizer = [[UILongPressGestureRecognizer alloc] initWithTarget:self
                                                                                            action:@selector(handleLongPress:)];
    // Making sure the allowable movement isn not too narrow
    longPressRecognizer.allowableMovement=100;
    // Important: The duration must be long enough to allow taps but not longer than the period in which view opens the magnifying glass
    longPressRecognizer.minimumPressDuration=0.3;

    [self addGestureRecognizer:longPressRecognizer];
    _longPressRecognizer = longPressRecognizer;

    // Override the _pdfView double tap gesture recognizer so that it doesn't confilict with custom double tap
    UITapGestureRecognizer *doubleTapEmptyRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self
                                                                                          action:@selector(handleDoubleTapEmpty:)];
    doubleTapEmptyRecognizer.numberOfTapsRequired = 2;
    [_pdfView addGestureRecognizer:doubleTapEmptyRecognizer];
    _doubleTapEmptyRecognizer = doubleTapEmptyRecognizer;
    
    // Adicionar reconhecedores de swipe para todas as direções
    UISwipeGestureRecognizer *swipeLeftRecognizer = [[UISwipeGestureRecognizer alloc] initWithTarget:self
                                                                                               action:@selector(handleSwipe:)];
    swipeLeftRecognizer.direction = UISwipeGestureRecognizerDirectionLeft;
    swipeLeftRecognizer.delegate = self;
    [self addGestureRecognizer:swipeLeftRecognizer];
    _swipeLeftRecognizer = swipeLeftRecognizer;
    
    UISwipeGestureRecognizer *swipeRightRecognizer = [[UISwipeGestureRecognizer alloc] initWithTarget:self
                                                                                                action:@selector(handleSwipe:)];
    swipeRightRecognizer.direction = UISwipeGestureRecognizerDirectionRight;
    swipeRightRecognizer.delegate = self;
    [self addGestureRecognizer:swipeRightRecognizer];
    _swipeRightRecognizer = swipeRightRecognizer;
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer

{
    return !_singlePage;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer
{
    // Se um dos recognizers é o singleTap e o outro é tap de uma nota, não permitir simultâneo
    if ((gestureRecognizer == _singleTapRecognizer && [otherGestureRecognizer isKindOfClass:[UITapGestureRecognizer class]] && otherGestureRecognizer.view.tag == 3000) ||
        (otherGestureRecognizer == _singleTapRecognizer && [gestureRecognizer isKindOfClass:[UITapGestureRecognizer class]] && gestureRecognizer.view.tag == 3000)) {
        return NO;
    }

    return !_singlePage;
}

- (void)setScrollIndicators:(UIView *)view horizontal:(BOOL)horizontal vertical:(BOOL)vertical depth:(int)depth {
    // max depth, prevent infinite loop
    if (depth > 10) {
        return;
    }
    
    if ([view isKindOfClass:[UIScrollView class]]) {
        UIScrollView *scrollView = (UIScrollView *)view;
        scrollView.showsHorizontalScrollIndicator = horizontal;
        scrollView.showsVerticalScrollIndicator = vertical;
    }
    
    for (UIView *subview in view.subviews) {
        [self setScrollIndicators:subview horizontal:horizontal vertical:vertical depth:depth + 1];
    }
}

#pragma mark - Custom Methods

// Helper method to convert hex color string to UIColor
- (UIColor *)colorFromHexString:(NSString *)hexString {
    if (!hexString || hexString.length == 0) {
        return [UIColor blackColor]; // Default color
    }

    // Handle special case for transparent
    if ([hexString isEqualToString:@"transparent"]) {
        return [UIColor clearColor];
    }

    // Remove # if present
    NSString *cleanString = [hexString stringByReplacingOccurrencesOfString:@"#" withString:@""];

    // Check if it's a valid hex string
    if (cleanString.length != 6) {
        // If not a hex string, try to match predefined color names as fallback
        if ([hexString isEqualToString:@"white"]) return [UIColor whiteColor];
        if ([hexString isEqualToString:@"black"]) return [UIColor blackColor];
        if ([hexString isEqualToString:@"red"]) return [UIColor redColor];
        if ([hexString isEqualToString:@"blue"]) return [UIColor blueColor];
        if ([hexString isEqualToString:@"green"]) return [UIColor greenColor];
        if ([hexString isEqualToString:@"yellow"]) return [UIColor yellowColor];
        if ([hexString isEqualToString:@"gray"]) return [UIColor grayColor];
        if ([hexString isEqualToString:@"orange"]) return [UIColor orangeColor];

        return [UIColor blackColor]; // Default if no match
    }

    // Parse hex string
    unsigned int r, g, b;
    NSScanner *scanner;

    scanner = [NSScanner scannerWithString:[cleanString substringWithRange:NSMakeRange(0, 2)]];
    [scanner scanHexInt:&r];

    scanner = [NSScanner scannerWithString:[cleanString substringWithRange:NSMakeRange(2, 2)]];
    [scanner scanHexInt:&g];

    scanner = [NSScanner scannerWithString:[cleanString substringWithRange:NSMakeRange(4, 2)]];
    [scanner scanHexInt:&b];

    return [UIColor colorWithRed:(r / 255.0) green:(g / 255.0) blue:(b / 255.0) alpha:1.0];
}

// Método para adicionar uma subview sobre o PDF
- (void)addOverlaysToPDF
{
    // IMPORTANTE: Usar dispatch_async para garantir que o PDF está totalmente renderizado
    dispatch_async(dispatch_get_main_queue(), ^{
        NSLog(@"🔵 Iniciando addOverlaysToPDF");
        [self drawHotspots];
        [self drawTextNotes];
        [self drawNotes];
    });
}


- (void)drawHotspots {
    [self removeOverlaysWithTags:@[@1000]];
    NSError *error = nil;
    NSData *data = [_hotspots dataUsingEncoding:NSUTF8StringEncoding];
    NSArray *array = [NSJSONSerialization JSONObjectWithData:data
                                                options:0
                                                  error:&error];
    for(NSDictionary *hotspot in array) {
        NSString *type = hotspot[@"type"] ?: @"default";
        NSString *iconName = [NSString stringWithFormat:@"classification_%@", type];
        [self addHotSpotWithX:[hotspot[@"xPos"] floatValue] andY:[hotspot[@"yPos"] floatValue] iconName:iconName hotspotId:hotspot[@"uid"]];
    }
}

- (void)drawTextNotes {
    [self removeOverlaysWithTags:@[@3000]];
    NSError *error = nil;
    NSData *data = [_textNotes dataUsingEncoding:NSUTF8StringEncoding];
    NSArray *array = [NSJSONSerialization JSONObjectWithData:data
                                                options:0
                                                  error:&error];
    for(NSDictionary *note in array) {
        [self addTextNoteWithX:[note[@"xPos"] floatValue]
                          andY:[note[@"yPos"] floatValue]
                         width:[note[@"width"] floatValue]
                        height:[note[@"height"] floatValue]
                  annotationId:note[@"uid"]
                   initialText:note[@"lines"]  // Pass lines array as initialText
                      fontSize:16  // Default font size (will be overridden by line-specific sizes)
                     textColor:@"#000000"  // Default color (will be overridden by line-specific colors)
                   textOpacity:1  // Default opacity (will be overridden by line-specific opacity)
                   borderWidth:[note[@"borderSize"] floatValue]
                   borderColor:note[@"borderColor"]
                 borderOpacity:[note[@"borderOpacity"] floatValue]
               backgroundColor:note[@"backgroundColor"]
             backgroundOpacity:[note[@"backgroundOpacity"] floatValue]];  // Pass editing state
    }
}

- (void)drawNotes {
    [self removeOverlaysWithTags:@[@2000]];
    NSError *error = nil;
    NSData *data = [_notes dataUsingEncoding:NSUTF8StringEncoding];
    NSArray *array = [NSJSONSerialization JSONObjectWithData:data
                                                options:0
                                                  error:&error];
    for(NSDictionary *note in array) {
        [self addNoteWithX:[note[@"xPos"] floatValue]  andY:[note[@"yPos"] floatValue]  color:note[@"color"] annotationId:note[@"uid"]];
    }
}


- (void)handleSwipe:(UISwipeGestureRecognizer *)sender
{
    CGPoint point = [sender locationInView:self];
    PDFPage *pdfPage = [_pdfView pageForPoint:point nearest:NO];
    
    NSString *direction = @"";
    switch (sender.direction) {
        case UISwipeGestureRecognizerDirectionLeft:
            direction = @"left";
            break;
        case UISwipeGestureRecognizerDirectionRight:
            direction = @"right";
            break;
        default:
            direction = @"unknown";
            break;
    }
    
    UIScrollView *scrollView = nil;
    for (UIView *subview in _pdfView.subviews) {
        if ([subview isKindOfClass:[UIScrollView class]]) {
            scrollView = (UIScrollView *)subview;
            break;
        }
    }
    
    NSString *scrollPosition = @"middle";
    BOOL isAtLeftEdge = NO;
    BOOL isAtRightEdge = NO;
    
    if (scrollView) {
        CGFloat contentOffsetX = scrollView.contentOffset.x;
        CGFloat maxOffsetX = scrollView.contentSize.width - scrollView.bounds.size.width;
        
        CGFloat tolerance = 1.0;
        isAtLeftEdge = (contentOffsetX <= tolerance);
        isAtRightEdge = (contentOffsetX >= maxOffsetX - tolerance);
        
        if (_horizontal) {
            if (isAtLeftEdge) {
                scrollPosition = @"leftEdge";  // No início
            } else if (isAtRightEdge) {
                scrollPosition = @"rightEdge"; // No fim (não dá mais para ir à esquerda!)
            }
        }
    }
    
    if (pdfPage) {
        if ([direction isEqualToString:@"left"] && isAtRightEdge) {
            [self notifyOnChangeWithMessage:[[NSString alloc] initWithString:[NSString stringWithFormat:@"nextPage"]]];
        }
        
        // Se swipe à direita e já está na esquerda (início)
        if ([direction isEqualToString:@"right"] && isAtLeftEdge) {
            [self notifyOnChangeWithMessage:[[NSString alloc] initWithString:[NSString stringWithFormat:@"prevPage"]]];
        }
    }
}


- (void)addNoteWithX:(CGFloat)x
                andY:(CGFloat)y
               color:(NSString *)color
        annotationId:(NSString *)annotationId

{
    PDFPage *page = [_pdfDocument pageAtIndex:0];
    if (!page) {
        return;
    }

    CGRect originalPageBounds = [page boundsForBox:kPDFDisplayBoxMediaBox];
    CGRect pageBounds = [page boundsForBox:kPDFDisplayBoxCropBox];

    // Tamanho fixo na tela - dividir pelo scaleFactor para compensar o zoom
    // Quando zoom aumenta, o tamanho em coordenadas da página diminui para manter tamanho visual constante
    CGFloat fixedSizeOnScreen = 15 * pageBounds.size.width / originalPageBounds.size.width * [UIScreen mainScreen].scale;
    CGFloat noteSizeInPageCoords = fixedSizeOnScreen / _pdfView.scaleFactor;

    // Calcular posição do centro da nota
    CGFloat centerX = pageBounds.size.width * (x / 100);
    CGFloat centerY = pageBounds.size.height * (y / 100);
    CGFloat halfSize = noteSizeInPageCoords / 2.0;

    // Posicionar pelo centro (subtrair metade do tamanho)
    CGRect pdfRect = CGRectMake(centerX - halfSize,
                                centerY - halfSize,
                                noteSizeInPageCoords,
                                noteSizeInPageCoords);
    
    UIView *overlay = [[UIView alloc] initWithFrame:pdfRect];
    overlay.backgroundColor = [UIColor clearColor];
    overlay.tag = 2000;
    overlay.userInteractionEnabled = YES;
    overlay.accessibilityIdentifier = annotationId;
    overlay.layer.zPosition = 500; // À frente das notas de texto (100), atrás dos hotspots (1000)
    
    UIImage *playImage = [UIImage imageNamed:[NSString stringWithFormat:@"annotation_%@",color]];
    if (playImage) {
        UIImageView *imageView = [[UIImageView alloc] initWithImage:playImage];
        imageView.frame = CGRectMake(0, 0, pdfRect.size.width, pdfRect.size.height);
        imageView.contentMode = UIViewContentModeScaleAspectFit; // Manter proporção
        imageView.userInteractionEnabled = YES;
        
        [overlay addSubview:imageView];
    }
    
    // Adicionar gesture recognizer para movimentar a nota
    UIPanGestureRecognizer *panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleNotePan:)];
    panGesture.delegate = self;
    [overlay addGestureRecognizer:panGesture];

    // Adicionar gesture recognizer para tap na nota
    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleNoteTap:)];
    tapGesture.numberOfTapsRequired = 1;
    tapGesture.delegate = self;
    [overlay addGestureRecognizer:tapGesture];
    
    // Adicionar a view à página
    dispatch_async(dispatch_get_main_queue(), ^{
        // Pegar a view da página
        for (UIView *subview in self->_pdfView.subviews) {
            if ([subview isKindOfClass:[UIScrollView class]]) {
                UIScrollView *scrollView = (UIScrollView *)subview;
                for (UIView *pageView in scrollView.subviews) {
                    // Encontrar a view da página correta
                    [pageView addSubview:overlay];
                    break; // Por agora adicionar à primeira
                }
                break;
            }
        }
    });
}


- (void)addTextNoteWithX:(CGFloat)x
                    andY:(CGFloat)y
                   width:(CGFloat)widthPercent
                  height:(CGFloat)heightPercent
            annotationId:(NSString *)annotationId
             initialText:(NSArray *)initialText  // Changed to NSArray to accept array of line objects
                fontSize:(CGFloat)fontSize
               textColor:(NSString *)textColor
             textOpacity:(CGFloat)textOpacity
             borderWidth:(CGFloat)borderWidth
             borderColor:(NSString *)borderColorStr
           borderOpacity:(CGFloat)borderOpacity
         backgroundColor:(NSString *)backgroundColorStr
       backgroundOpacity:(CGFloat)backgroundOpacity
{
    PDFPage *page = [_pdfDocument pageAtIndex:0];
    if (!page) {
        return;
    }

    CGRect pageBounds = [page boundsForBox:kPDFDisplayBoxCropBox];

    // Calcular width e height em coordenadas da página (baseado em percentagem)
    CGFloat noteWidth = pageBounds.size.width * (widthPercent / 100) + borderWidth*2;
    CGFloat noteHeight = pageBounds.size.height * (heightPercent / 100) + borderWidth*2;

    // Margens para os controlos de edição
    CGFloat leftMargin = 33;
    CGFloat topMargin = 16;
    CGFloat rightMargin = 13;
    CGFloat bottomMargin = 16;

    // Para notas de texto: x,y representa o canto superior esquerdo da nota (não o centro)
    CGFloat noteLeftX = pageBounds.size.width * (x / 100);
    CGFloat noteTopY = pageBounds.size.height * (y / 100);

    // pdfRect usado para anotação (não usado realmente, mas mantém compatibilidade)
    CGRect pdfRect = CGRectMake(noteLeftX, noteTopY, noteWidth, noteHeight);

    // Container maior que inclui nota + controlos
    CGFloat containerWidth = noteWidth + 6 + leftMargin + rightMargin;
    CGFloat containerHeight = noteHeight + 6 + topMargin + bottomMargin;

    // Posição do container: canto superior esquerdo da nota está em (noteLeftX, noteTopY)
    // Container começa leftMargin à esquerda e topMargin acima
    CGRect containerRect = CGRectMake(noteLeftX - leftMargin,
                                      noteTopY - topMargin,
                                      containerWidth,
                                      containerHeight);

    // Container principal
    UIView *container = [[UIView alloc] initWithFrame:containerRect];
    container.backgroundColor = [UIColor clearColor];
    container.tag = 3000;
    container.userInteractionEnabled = YES;
    container.accessibilityIdentifier = annotationId;
    container.layer.zPosition = 100; // Por baixo dos hotspots (zPosition = 1000)

    // Vista da nota (dentro do container)
    CGRect noteFrame = CGRectMake(leftMargin, topMargin, noteWidth + 6, noteHeight + 6);
    UIView *noteView = [[UIView alloc] initWithFrame:noteFrame];
    noteView.layer.cornerRadius = 0.0;  // Cantos retos (sem arredondamento)
    noteView.clipsToBounds = YES;  // Cortar conteúdo que ultrapassa os limites
    noteView.userInteractionEnabled = YES;
    noteView.tag = 3001;

    if(![backgroundColorStr isEqual:@"transparent"]) {
        // Cor de fundo com opacidade - usando helper method para suportar hex colors
        UIColor *backgroundUIColor = [self colorFromHexString:backgroundColorStr];
        // Aplicar opacidade ao fundo (clamping entre 0.0 e 1.0)
        CGFloat clampedBackgroundOpacity = MAX(0.0, MIN(1.0, backgroundOpacity));
        noteView.backgroundColor = [backgroundUIColor colorWithAlphaComponent:clampedBackgroundOpacity];
    }

    // Configuração da borda - ajustar para o zoom atual
    CGFloat currentScale = _scale > 0 ? _scale : 1.0;
    CGFloat adjustedBorderWidth = borderWidth / currentScale;
    noteView.layer.borderWidth = adjustedBorderWidth;

    // Guardar borderWidth original para ajustar com zoom
    objc_setAssociatedObject(noteView, "originalBorderWidth", @(borderWidth), OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    // Cor da borda - usando helper method para suportar hex colors
    UIColor *borderUIColor = [self colorFromHexString:borderColorStr];

    // Aplicar opacidade à borda (clamping entre 0.0 e 1.0)
    CGFloat clampedBorderOpacity = MAX(0.0, MIN(1.0, borderOpacity));
    noteView.layer.borderColor = [[borderUIColor colorWithAlphaComponent:clampedBorderOpacity] CGColor];

    // Build attributed string from lines array
    NSMutableAttributedString *attributedText = [[NSMutableAttributedString alloc] init];

    if (initialText && [initialText isKindOfClass:[NSArray class]] && initialText.count > 0) {
        for (NSInteger i = 0; i < initialText.count; i++) {
            NSDictionary *line = initialText[i];

            // Get line properties
            NSString *text = line[@"text"] ?: @"";
            CGFloat lineFontSize = [line[@"fontSize"] floatValue] ?: fontSize;
            NSString *lineColorStr = line[@"fontColor"] ?: textColor;
            CGFloat lineOpacity = line[@"fontOpacity"] ? [line[@"fontOpacity"] floatValue] : textOpacity;

            // Convert color using helper method
            UIColor *lineColor = [self colorFromHexString:lineColorStr];
            UIColor *lineColorWithOpacity = [lineColor colorWithAlphaComponent:MAX(0.0, MIN(1.0, lineOpacity))];

            // Paragraph style para reduzir espaço entre linhas
            NSMutableParagraphStyle *paragraphStyle = [[NSMutableParagraphStyle alloc] init];
            paragraphStyle.lineSpacing = -58;  // Valor negativo reduz espaçamento entre linhas
            paragraphStyle.paragraphSpacing = -10;
            paragraphStyle.lineHeightMultiple = 0.70;
            paragraphStyle.lineBreakMode = NSLineBreakByWordWrapping;  // Quebrar por palavras

            // Create attributed string for this line
            NSDictionary *attributes = @{
                NSFontAttributeName: [UIFont systemFontOfSize:lineFontSize],
                NSForegroundColorAttributeName: lineColorWithOpacity,
                NSParagraphStyleAttributeName: paragraphStyle
            };

            NSAttributedString *lineAttrString = [[NSAttributedString alloc] initWithString:text attributes:attributes];
            [attributedText appendAttributedString:lineAttrString];

            // Add newline if not the last line
            if (i < initialText.count - 1) {
                NSAttributedString *newline = [[NSAttributedString alloc] initWithString:@"\n" attributes:attributes];
                [attributedText appendAttributedString:newline];
            }
        }
    } else {
        // Fallback for backward compatibility (if initialText is not an array)
        UIColor *textUIColor = [self colorFromHexString:textColor];
        CGFloat clampedTextOpacity = MAX(0.0, MIN(1.0, textOpacity));
        UIColor *colorWithOpacity = [textUIColor colorWithAlphaComponent:clampedTextOpacity];

        // Paragraph style para reduzir espaço entre linhas
        NSMutableParagraphStyle *paragraphStyle = [[NSMutableParagraphStyle alloc] init];
        paragraphStyle.lineSpacing = -58;  // Valor negativo reduz espaçamento entre linhas
        paragraphStyle.paragraphSpacing = -10;
        paragraphStyle.lineHeightMultiple = 0.70;
        paragraphStyle.lineBreakMode = NSLineBreakByWordWrapping;  // Quebrar por palavras

        NSDictionary *attributes = @{
            NSFontAttributeName: [UIFont systemFontOfSize:fontSize],
            NSForegroundColorAttributeName: colorWithOpacity,
            NSParagraphStyleAttributeName: paragraphStyle
        };

        NSString *fallbackText = @"";
        attributedText = [[NSMutableAttributedString alloc] initWithString:fallbackText attributes:attributes];
    }

    // Padding consistente em todos os lados - usa borderWidth ajustado ao zoom
    CGFloat textPadding = adjustedBorderWidth + 2;
    CGRect textFrame = CGRectMake(textPadding, textPadding,
                                  noteView.bounds.size.width - (textPadding * 2),
                                  noteView.bounds.size.height - (textPadding * 2));

    CATextLayer *textLayer = [CATextLayer layer];
    textLayer.frame = textFrame;
    textLayer.contentsScale = [UIScreen mainScreen].scale * 5;

    // Configurar o attributed string no CATextLayer
    textLayer.string = attributedText;
    textLayer.wrapped = YES;
    textLayer.truncationMode = kCATruncationNone;
    textLayer.alignmentMode = kCAAlignmentLeft;

    // Guardar o attributed text para poder redesenhar durante resize
    objc_setAssociatedObject(noteView, "attributedText", attributedText, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    [noteView.layer addSublayer:textLayer];

    [container addSubview:noteView];

    // === BORDA DOTTED DE SELEÇÃO ===
    CGFloat borderOffset = 5.0; // 5 pixels afastada da nota
    CGRect selectionBorderFrame = CGRectMake(leftMargin - borderOffset,
                                             topMargin - borderOffset,
                                             noteWidth + 6 + (borderOffset * 2),
                                             noteHeight + 6 + (borderOffset * 2));

    UIView *selectionBorder = [[UIView alloc] initWithFrame:selectionBorderFrame];
    selectionBorder.backgroundColor = [UIColor clearColor];
    selectionBorder.tag = 4007;
    if(_clickedTextNoteId != nil && [_clickedTextNoteId isEqual:annotationId]) {
        selectionBorder.hidden = NO;
    }
    else {
        selectionBorder.hidden = YES;
    }

    // Criar borda dotted usando CAShapeLayer (sem lado esquerdo)
    CAShapeLayer *dottedBorder = [CAShapeLayer layer];
    dottedBorder.strokeColor = [UIColor colorWithRed:0.2 green:0.4 blue:0.8 alpha:1.0].CGColor;
    dottedBorder.fillColor = nil;
    dottedBorder.lineDashPattern = @[@4, @4]; // 4 pixels traço, 4 pixels espaço
    dottedBorder.lineWidth = 2.0;
    dottedBorder.frame = selectionBorder.bounds;

    // Criar path personalizado sem lado esquerdo e sem cantos arredondados (apenas top, right, bottom)
    UIBezierPath *borderPath = [UIBezierPath bezierPath];
    CGRect bounds = selectionBorder.bounds;

    // Começar no canto superior esquerdo
    [borderPath moveToPoint:CGPointMake(0, 0)];

    // Linha superior
    [borderPath addLineToPoint:CGPointMake(bounds.size.width, 0)];

    // Linha direita
    [borderPath addLineToPoint:CGPointMake(bounds.size.width, bounds.size.height)];

    // Linha inferior
    [borderPath addLineToPoint:CGPointMake(0, bounds.size.height)];

    dottedBorder.path = borderPath.CGPath;
    [selectionBorder.layer addSublayer:dottedBorder];

    [container addSubview:selectionBorder];

    // === CONTROLOS DE EDIÇÃO ===
    CGFloat btnSize = 16;
    UIColor *btnColor = [UIColor colorWithRed:0.2 green:0.5 blue:0.9 alpha:0.9];  // Mesma cor da side view
    UIColor *btnBorderColor = [UIColor colorWithRed:0.15 green:0.4 blue:0.8 alpha:1.0];  // Borda levemente mais escura

    // TOP MIDDLE - sobre a borda dotted
    UIView *topMid = [[UIView alloc] initWithFrame:CGRectMake(leftMargin + (noteWidth + 6)/2 - btnSize/2, topMargin - borderOffset - btnSize/2, btnSize, btnSize)];
    topMid.backgroundColor = btnColor;
    topMid.layer.borderWidth = 0;
    topMid.layer.cornerRadius = btnSize/2;  // Perfeitamente redondo
    topMid.tag = 4001;
    if(_clickedTextNoteId != nil && [_clickedTextNoteId isEqual:annotationId]) {
        topMid.hidden = NO;
    }
    else {
        topMid.hidden = YES;
    }
    topMid.userInteractionEnabled = YES;
    UIPanGestureRecognizer *topMidPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleResizePan:)];
    [topMid addGestureRecognizer:topMidPan];
    [container addSubview:topMid];

    // TOP RIGHT - sobre a borda dotted
    UIView *topRight = [[UIView alloc] initWithFrame:CGRectMake(leftMargin + noteWidth + 6 + borderOffset - btnSize/2, topMargin - borderOffset - btnSize/2, btnSize, btnSize)];
    topRight.backgroundColor = btnColor;
    topRight.layer.borderWidth = 0;
    topRight.layer.cornerRadius = btnSize/2;  // Perfeitamente redondo
    topRight.tag = 4002;
    if(_clickedTextNoteId != nil && [_clickedTextNoteId isEqual:annotationId]) {
        topRight.hidden = NO;
    }
    else {
        topRight.hidden = YES;
    }
    topRight.userInteractionEnabled = YES;
    UIPanGestureRecognizer *topRightPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleResizePan:)];
    [topRight addGestureRecognizer:topRightPan];
    [container addSubview:topRight];

    // MIDDLE RIGHT - sobre a borda dotted
    UIView *midRight = [[UIView alloc] initWithFrame:CGRectMake(leftMargin + noteWidth + 6 + borderOffset - btnSize/2, topMargin + (noteHeight + 6)/2 - btnSize/2, btnSize, btnSize)];
    midRight.backgroundColor = btnColor;
    midRight.layer.borderWidth = 0;
    midRight.layer.cornerRadius = btnSize/2;  // Perfeitamente redondo
    midRight.tag = 4003;
    if(_clickedTextNoteId != nil && [_clickedTextNoteId isEqual:annotationId]) {
        midRight.hidden = NO;
    }
    else {
        midRight.hidden = YES;
    }
    midRight.userInteractionEnabled = YES;
    UIPanGestureRecognizer *midRightPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleResizePan:)];
    [midRight addGestureRecognizer:midRightPan];
    [container addSubview:midRight];

    // BOTTOM RIGHT - sobre a borda dotted
    UIView *bottomRight = [[UIView alloc] initWithFrame:CGRectMake(leftMargin + noteWidth + 6 + borderOffset - btnSize/2, topMargin + noteHeight + 6 + borderOffset - btnSize/2, btnSize, btnSize)];
    bottomRight.backgroundColor = btnColor;
    bottomRight.layer.borderWidth = 0;
    bottomRight.layer.cornerRadius = btnSize/2;  // Perfeitamente redondo
    bottomRight.tag = 4004;
    if(_clickedTextNoteId != nil && [_clickedTextNoteId isEqual:annotationId]) {
        bottomRight.hidden = NO;
    }
    else {
        bottomRight.hidden = YES;
    }
    bottomRight.userInteractionEnabled = YES;
    UIPanGestureRecognizer *bottomRightPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleResizePan:)];
    [bottomRight addGestureRecognizer:bottomRightPan];
    [container addSubview:bottomRight];

    // BOTTOM MIDDLE - sobre a borda dotted
    UIView *bottomMid = [[UIView alloc] initWithFrame:CGRectMake(leftMargin + (noteWidth + 6)/2 - btnSize/2, topMargin + noteHeight + 6 + borderOffset - btnSize/2, btnSize, btnSize)];
    bottomMid.backgroundColor = btnColor;
    bottomMid.layer.borderWidth = 0;
    bottomMid.layer.cornerRadius = btnSize/2;  // Perfeitamente redondo
    bottomMid.tag = 4005;
    if(_clickedTextNoteId != nil && [_clickedTextNoteId isEqual:annotationId]) {
        bottomMid.hidden = NO;
    }
    else {
        bottomMid.hidden = YES;
    }
    bottomMid.userInteractionEnabled = YES;
    UIPanGestureRecognizer *bottomMidPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleResizePan:)];
    [bottomMid addGestureRecognizer:bottomMidPan];
    [container addSubview:bottomMid];

    // Vista lateral azul - afastada 5 pixels da nota
    CGFloat sideViewWidth = leftMargin - borderOffset; // Largura da sideView deixando 5px de espaço
    UIView *sideView = [[UIView alloc] initWithFrame:CGRectMake(0,
                                                                  topMargin - borderOffset,
                                                                  sideViewWidth,
                                                                  noteHeight + 6 + (borderOffset * 2))];
    sideView.backgroundColor = [UIColor colorWithRed:0.2 green:0.5 blue:0.9 alpha:0.9];
    sideView.layer.cornerRadius = 4.0;
    sideView.tag = 4006;
    if(_clickedTextNoteId != nil && [_clickedTextNoteId isEqual:annotationId]) {
        sideView.hidden = NO;
    }
    else {
        sideView.hidden = YES;
    }

    // Ícone de arrastar (3 linhas horizontais) - centralizado na sideView
    CGFloat sideViewHeight = noteHeight + 6 + (borderOffset * 2);
    CGFloat iconWidth = sideViewWidth * 0.5; // 50% da largura da sideView
    CGFloat iconX = (sideViewWidth - iconWidth) / 2; // Centralizar horizontalmente

    for (int i = 0; i < 3; i++) {
        UIView *line = [[UIView alloc] initWithFrame:CGRectMake(iconX, sideViewHeight/2 - 6 + i*5, iconWidth, 2)];
        line.backgroundColor = [UIColor whiteColor];
        line.layer.cornerRadius = 1.0;
        [sideView addSubview:line];
    }
    [container addSubview:sideView];

    // Gesture recognizers
    UIPanGestureRecognizer *panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleNotePan:)];
    panGesture.delegate = self;
    [container addGestureRecognizer:panGesture];

    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleNoteTap:)];
    tapGesture.numberOfTapsRequired = 1;
    tapGesture.delegate = self;
    [container addGestureRecognizer:tapGesture];

    dispatch_async(dispatch_get_main_queue(), ^{
        for (UIView *subview in self->_pdfView.subviews) {
            if ([subview isKindOfClass:[UIScrollView class]]) {
                UIScrollView *scrollView = (UIScrollView *)subview;
                for (UIView *pageView in scrollView.subviews) {
                    [pageView addSubview:container];
                    break;
                }
                break;
            }
        }
    });
}


- (void)addHotSpotWithX:(CGFloat)x
                   andY:(CGFloat)y
         iconName:(NSString *)iconName
              hotspotId:(NSString *)hotspotId
{
    PDFPage *page = [_pdfDocument pageAtIndex:0];
    if (!page) {
        return;
    }

    CGRect pageBounds = [page boundsForBox:kPDFDisplayBoxCropBox];
    CGRect pdfRect = CGRectMake(pageBounds.size.width*(x/100), pageBounds.size.height*(y/100), pageBounds.size.width*0.048, pageBounds.size.width*0.048);
    UIView *overlay = [[UIView alloc] initWithFrame:pdfRect];
    overlay.backgroundColor = [UIColor clearColor];
    overlay.tag = 1000;
    overlay.userInteractionEnabled = YES;
    overlay.accessibilityIdentifier = hotspotId;
    overlay.layer.zPosition = 1000; // Garantir que fica à frente do conteúdo PDF
    
    UIImage *playImage = [UIImage imageNamed:iconName];
    if (playImage) {
        UIImageView *imageView = [[UIImageView alloc] initWithImage:playImage];
        imageView.frame = CGRectMake(0, 0, pdfRect.size.width, pdfRect.size.height);
        imageView.contentMode = UIViewContentModeScaleAspectFit; // Manter proporção
        imageView.userInteractionEnabled = YES;
        imageView.tag = 2000;
        
        [overlay addSubview:imageView];
    }
    
    // Se não for interativo, adicionar tap gesture no overlay também
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(hotspotTapped:)];
    tap.cancelsTouchesInView = NO;
    [overlay addGestureRecognizer:tap];
    
    //[page addAnnotation:[[PDFAnnotation alloc] initWithBounds:pdfRect forType:PDFAnnotationSubtypeWidget withProperties:nil]];
    
    // Adicionar a view à página
    dispatch_async(dispatch_get_main_queue(), ^{
        // Pegar a view da página
        for (UIView *subview in self->_pdfView.subviews) {
            if ([subview isKindOfClass:[UIScrollView class]]) {
                UIScrollView *scrollView = (UIScrollView *)subview;
                for (UIView *pageView in scrollView.subviews) {
                    // Encontrar a view da página correta
                    [pageView addSubview:overlay];
                    break; // Por agora adicionar à primeira
                }
                break;
            }
        }
    });
}

// Handler para tap em overlay interativo
- (void)hotspotTapped:(UITapGestureRecognizer *)recognizer
{
    UIView *button = recognizer.view;
    
    [UIView animateWithDuration:0.15 animations:^{
        button.transform = CGAffineTransformMakeScale(0.85, 0.85);
        button.alpha = 0.7;
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.15 animations:^{
            button.transform = CGAffineTransformIdentity;
            button.alpha = 1.0;
        }];
    }];
    // 🆔 Recuperar o identificador do hotspot
    NSString *hotspotId = button.accessibilityIdentifier ?: @"unknown";
    // 📤 Enviar evento para JavaScript com o ID do hotspot
    [self notifyOnChangeWithMessage:[[NSString alloc] initWithString:[NSString stringWithFormat:@"hotspotTapped|%@", hotspotId]]];
}


- (void)handleImageTap:(UIGestureRecognizer *)recognizer
{
    UIView *view = recognizer.view;
    // Feedback visual - animar a view
    [UIView animateWithDuration:0.15 animations:^{
        view.transform = CGAffineTransformMakeScale(0.85, 0.85);
        view.alpha = 0.7;
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.15 animations:^{
            view.transform = CGAffineTransformIdentity;
            view.alpha = 1.0;
        }];
    }];
}

// Handler para tap na nota - retorna posição em relação à vista do PDF
- (void)handleNoteTap:(UITapGestureRecognizer *)recognizer
{
    UIView *noteView = recognizer.view;
    NSString *noteId = noteView.accessibilityIdentifier ?: @"note";

    // Se tocar numa nota diferente da que está selecionada, esconder controlos
    if (_clickedTextNoteId && ![_clickedTextNoteId isEqualToString:noteId]) {
        NSLog(@"hideAllTextNoteEditingControls 3");
        [self hideAllTextNoteEditingControls];
        _clickedTextNoteId = nil;
    }

    // Verificar se é nota de texto (tag 3000) ou nota normal (tag 2000)
    if (noteView.tag == 3000) {
        // Nota de texto - mostrar controlos de edição e UITextView
        NSLog(@"📝 Tap em nota de texto - mostrando controlos e edição");
        _clickedTextNoteId = noteId;
        [self showTextNoteEditingControlsForNoteId:noteId];

        // Encontrar o noteView dentro do container
        UIView *container = noteView;
        UIView *actualNoteView = [container viewWithTag:3001];
        if (!actualNoteView) return;

        // Verificar se já existe UITextView
        UITextView *textView = [actualNoteView viewWithTag:3002];

        if (!textView) {
            // Criar UITextView para edição
            CGFloat textPadding = actualNoteView.layer.borderWidth + 2;
            CGRect textFrame = CGRectMake(textPadding, textPadding,
                                         actualNoteView.bounds.size.width - (textPadding * 2),
                                         actualNoteView.bounds.size.height - (textPadding * 2));

            textView = [[UITextView alloc] initWithFrame:textFrame];
            textView.backgroundColor = [UIColor clearColor];
            textView.tintColor = [UIColor blueColor];
            textView.textAlignment = NSTextAlignmentLeft;
            textView.textContainerInset = UIEdgeInsetsZero;
            textView.textContainer.lineFragmentPadding = 0;
            textView.scrollEnabled = NO;
            textView.tag = 3002;
            textView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            textView.delegate = self;

            // Obter o attributedText guardado e guardar separadamente (para restaurar depois)
            NSAttributedString *storedText = objc_getAssociatedObject(actualNoteView, "attributedText");
            if (storedText) {
                // Guardar o texto original (não transparente) num local separado
                objc_setAssociatedObject(textView, "originalText", storedText, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

                // Criar versão transparente para a UITextView
                NSMutableAttributedString *transparentText = [[NSMutableAttributedString alloc] initWithAttributedString:storedText];
                [transparentText addAttribute:NSForegroundColorAttributeName
                                        value:[UIColor clearColor]
                                        range:NSMakeRange(0, transparentText.length)];
                textView.attributedText = transparentText;

                // Configurar typing attributes para novo texto ser transparente
                textView.typingAttributes = @{
                    NSForegroundColorAttributeName: [UIColor clearColor],
                    NSFontAttributeName: [UIFont systemFontOfSize:14]
                };
            }

            [actualNoteView addSubview:textView];
        } else {
            // Se já existe, atualizar com texto transparente
            NSAttributedString *storedText = objc_getAssociatedObject(actualNoteView, "attributedText");
            if (storedText) {
                objc_setAssociatedObject(textView, "originalText", storedText, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

                NSMutableAttributedString *transparentText = [[NSMutableAttributedString alloc] initWithAttributedString:storedText];
                [transparentText addAttribute:NSForegroundColorAttributeName
                                        value:[UIColor clearColor]
                                        range:NSMakeRange(0, transparentText.length)];
                textView.attributedText = transparentText;

                textView.typingAttributes = @{
                    NSForegroundColorAttributeName: [UIColor clearColor],
                    NSFontAttributeName: [UIFont systemFontOfSize:14]
                };
            }
        }

        // Mostrar e ativar UITextView para edição
        textView.hidden = NO;
        textView.editable = YES;
        textView.userInteractionEnabled = YES;

        // Mostrar teclado
        dispatch_async(dispatch_get_main_queue(), ^{
            [textView becomeFirstResponder];
        });

        // Enviar evento noteTapped para JavaScript
        CGPoint centerInPdfView = [noteView.superview convertPoint:noteView.center toView:_pdfView];
        CGFloat pdfViewWidth = _pdfView.bounds.size.width;
        CGFloat pdfViewHeight = _pdfView.bounds.size.height;
        CGFloat xPos = centerInPdfView.x;
        CGFloat yPos = centerInPdfView.y;
        CGFloat xPercent = (xPos / pdfViewWidth) * 100.0;
        CGFloat yPercent = (yPos / pdfViewHeight) * 100.0;
        xPercent = MAX(0.0, MIN(xPercent, 100.0));
        yPercent = MAX(0.0, MIN(yPercent, 100.0));
        [self notifyOnChangeWithMessage:[[NSString alloc] initWithString:[NSString stringWithFormat:@"noteTapped|%@|%f|%f", noteId, xPercent, yPercent]]];
        NSLog(@"👆 Nota de texto tocada: ID=%@, centro em x=%.2fpx (%.2f%%), y=%.2fpx (%.2f%%) em relação à vista do PDF", noteId, xPos, xPercent, yPos, yPercent);

        return;
    }

    // Nota normal (tag 2000) - enviar evento
    // Converter o centro da nota para coordenadas da vista do PDF
    CGPoint centerInPdfView = [noteView.superview convertPoint:noteView.center toView:_pdfView];

    // Obter dimensões da vista do PDF
    CGFloat pdfViewWidth = _pdfView.bounds.size.width;
    CGFloat pdfViewHeight = _pdfView.bounds.size.height;

    // Calcular posição em pixels em relação à vista (centro da nota)
    CGFloat xPos = centerInPdfView.x;
    CGFloat yPos = centerInPdfView.y;

    // Calcular posição percentual em relação à vista
    CGFloat xPercent = (xPos / pdfViewWidth) * 100.0;
    CGFloat yPercent = (yPos / pdfViewHeight) * 100.0;

    // Garantir que as percentagens nunca sejam negativas (clamping entre 0 e 100)
    xPercent = MAX(0.0, MIN(xPercent, 100.0));
    yPercent = MAX(0.0, MIN(yPercent, 100.0));

    // Enviar notificação para JavaScript com posição em relação à vista (centro)
    [self notifyOnChangeWithMessage:[[NSString alloc] initWithString:[NSString stringWithFormat:@"noteTapped|%@|%f|%f", noteId, xPercent, yPercent]]];

    NSLog(@"👆 Nota tocada: ID=%@, centro em x=%.2fpx (%.2f%%), y=%.2fpx (%.2f%%) em relação à vista do PDF", noteId, xPos, xPercent, yPos, yPercent);
}

// Handler para movimentar notas sobre a página
- (void)handleNotePan:(UIPanGestureRecognizer *)recognizer
{
    UIView *noteView = recognizer.view;

    if (recognizer.state == UIGestureRecognizerStateBegan) {
        NSString *noteId = noteView.accessibilityIdentifier;

        // Se começar a mover uma nota diferente da que está selecionada, esconder controlos
        if (_clickedTextNoteId && ![_clickedTextNoteId isEqualToString:noteId]) {
            NSLog(@"hideAllTextNoteEditingControls 4");
            [self hideAllTextNoteEditingControls];
            _clickedTextNoteId = nil;
        }

        // Se for nota de texto (tag 3000), mostrar controlos de edição
        if (noteView.tag == 3000) {
            if (noteId) {
                _clickedTextNoteId = noteId;
                [self showTextNoteEditingControlsForNoteId:noteId];
                NSLog(@"📝 Pan iniciado - mostrando controlos para nota: %@", noteId);
            }
        }

        // Desabilitar scroll da página enquanto move a nota
        for (UIView *subview in _pdfView.subviews) {
            if ([subview isKindOfClass:[UIScrollView class]]) {
                UIScrollView *scrollView = (UIScrollView *)subview;
                scrollView.scrollEnabled = NO;
            }
        }

        // Desabilitar swipe gestures enquanto move a nota
        _swipeLeftRecognizer.enabled = NO;
        _swipeRightRecognizer.enabled = NO;
        
        [self notifyOnChangeWithMessage:[[NSString alloc] initWithString:[NSString stringWithFormat:@"noteTapped|%@|%f|%f", noteId, 0, 0]]];
    }

    if (recognizer.state == UIGestureRecognizerStateBegan || recognizer.state == UIGestureRecognizerStateChanged) {
        // Obter a translação do gesto
        CGPoint translation = [recognizer translationInView:noteView.superview];

        // Guardar posição atual antes de mover
        CGPoint oldCenter = noteView.center;

        // Calcular nova posição desejada
        CGPoint newCenter = CGPointMake(oldCenter.x + translation.x, oldCenter.y + translation.y);

        // Obter os limites da página
        CGRect pageViewBounds = noteView.superview.bounds;

        // Para notas de texto (tag 3000), limitar baseado na nota real (tag 3001)
        // Para notas normais (tag 2000), usar a própria nota
        CGFloat noteHalfWidth, noteHalfHeight;
        CGPoint noteOffset = CGPointZero;

        if (noteView.tag == 3000) {
            // Container de nota de texto - encontrar a nota real dentro dele
            UIView *realNote = [noteView viewWithTag:3001];
            if (realNote) {
                // Usar dimensões da nota real
                noteHalfWidth = realNote.bounds.size.width / 2;
                noteHalfHeight = realNote.bounds.size.height / 2;

                // Calcular offset entre centro do container e centro da nota real
                CGPoint realNoteCenter = [noteView convertPoint:realNote.center toView:noteView.superview];
                noteOffset = CGPointMake(realNoteCenter.x - noteView.center.x, realNoteCenter.y - noteView.center.y);
            } else {
                // Fallback se não encontrar a nota real
                noteHalfWidth = noteView.bounds.size.width / 2;
                noteHalfHeight = noteView.bounds.size.height / 2;
            }
        } else {
            // Nota normal - usar a própria nota
            noteHalfWidth = noteView.bounds.size.width / 2;
            noteHalfHeight = noteView.bounds.size.height / 2;
        }

        // Calcular posição da nota real com a nova posição do container
        CGPoint realNoteNewCenter = CGPointMake(newCenter.x + noteOffset.x, newCenter.y + noteOffset.y);

        // Limitar a posição da nota real aos limites da página
        CGPoint clampedRealNoteCenter;
        clampedRealNoteCenter.x = MAX(noteHalfWidth, MIN(realNoteNewCenter.x, pageViewBounds.size.width - noteHalfWidth));
        clampedRealNoteCenter.y = MAX(noteHalfHeight, MIN(realNoteNewCenter.y, pageViewBounds.size.height - noteHalfHeight));

        // Calcular centro do container baseado na posição clamped da nota real
        CGPoint clampedCenter = CGPointMake(clampedRealNoteCenter.x - noteOffset.x, clampedRealNoteCenter.y - noteOffset.y);

        // Atualizar a posição do container
        noteView.center = clampedCenter;

        // Calcular quanto realmente movemos (pode ser menos se atingiu o limite)
        CGPoint actualMovement = CGPointMake(clampedCenter.x - oldCenter.x, clampedCenter.y - oldCenter.y);

        // Resetar a translação apenas pelo movimento real aplicado
        [recognizer setTranslation:CGPointMake(translation.x - actualMovement.x, translation.y - actualMovement.y) inView:noteView.superview];

    } else if (recognizer.state == UIGestureRecognizerStateEnded || recognizer.state == UIGestureRecognizerStateCancelled) {
        // Reabilitar scroll da página apenas se scrollEnabled estiver ativo
        if (_scrollEnabled) {
            for (UIView *subview in _pdfView.subviews) {
                if ([subview isKindOfClass:[UIScrollView class]]) {
                    UIScrollView *scrollView = (UIScrollView *)subview;
                    scrollView.scrollEnabled = YES;
                }
            }
        }

        // Reabilitar swipe gestures
        _swipeLeftRecognizer.enabled = YES;
        _swipeRightRecognizer.enabled = YES;

        // Calcular posição percentual em relação à página
        if (recognizer.state == UIGestureRecognizerStateEnded) {
            PDFPage *page = [_pdfDocument pageAtIndex:0];
            if (page) {
                CGRect pageBounds = [page boundsForBox:kPDFDisplayBoxCropBox];
                CGFloat xPercent, yPercent;
                NSString *noteId = noteView.accessibilityIdentifier ?: @"note";

                // Para notas de texto (tag 3000), usar canto superior esquerdo da nota real
                // Para notas normais (tag 2000), usar centro
                if (noteView.tag == 3000) {
                    // Nota de texto - encontrar nota real dentro do container
                    UIView *realNote = [noteView viewWithTag:3001];
                    if (realNote) {
                        // Converter canto superior esquerdo da nota real para coordenadas da página
                        CGPoint topLeft = [noteView convertPoint:realNote.frame.origin toView:noteView.superview];
                        xPercent = (topLeft.x / pageBounds.size.width) * 100.0;
                        yPercent = (topLeft.y / pageBounds.size.height) * 100.0;
                        NSLog(@"📍 Nota de texto movida (canto superior esquerdo): x=%.2f%%, y=%.2f%%", xPercent, yPercent);
                    } else {
                        // Fallback para centro se não encontrar nota real
                        CGFloat centerX = noteView.center.x;
                        CGFloat centerY = noteView.center.y;
                        xPercent = (centerX / pageBounds.size.width) * 100.0;
                        yPercent = (centerY / pageBounds.size.height) * 100.0;
                        NSLog(@"📍 Nota movida (centro - fallback): x=%.2f%%, y=%.2f%%", xPercent, yPercent);
                    }
                } else {
                    // Nota normal - usar centro
                    CGFloat centerX = noteView.center.x;
                    CGFloat centerY = noteView.center.y;
                    xPercent = (centerX / pageBounds.size.width) * 100.0;
                    yPercent = (centerY / pageBounds.size.height) * 100.0;
                    NSLog(@"📍 Nota normal movida (centro): x=%.2f%%, y=%.2f%%", xPercent, yPercent);
                }

                // Notificar JavaScript sobre a nova posição
                [self notifyOnChangeWithMessage:[[NSString alloc] initWithString:[NSString stringWithFormat:@"noteMoved|%@|%f|%f", noteId, xPercent, yPercent]]];
            }
        }
    }
}


// Handler para redimensionar notas através dos botões de resize
- (void)handleResizePan:(UIPanGestureRecognizer *)recognizer
{
    UIView *resizeButton = recognizer.view;
    UIView *container = resizeButton.superview; // Container da nota (tag 3000)

    if (!container || container.tag != 3000) return;

    // Encontrar elementos dentro do container
    UIView *noteView = [container viewWithTag:3001];
    UIView *selectionBorder = [container viewWithTag:4007];
    UIView *sideView = [container viewWithTag:4006];

    // Encontrar CATextLayer (primeira sublayer do noteView)
    CATextLayer *textLayer = nil;
    if (noteView.layer.sublayers.count > 0) {
        for (CALayer *sublayer in noteView.layer.sublayers) {
            if ([sublayer isKindOfClass:[CATextLayer class]]) {
                textLayer = (CATextLayer *)sublayer;
                break;
            }
        }
    }

    if (!noteView) return;

    // Constantes
    CGFloat leftMargin = 33;
    CGFloat topMargin = 16;
    CGFloat rightMargin = 13;
    CGFloat bottomMargin = 16;
    CGFloat borderOffset = 5.0;
    CGFloat minNoteWidth = 50.0;  // Largura mínima da nota
    CGFloat minNoteHeight = 30.0; // Altura mínima da nota
    CGFloat btnSize = 16;

    if (recognizer.state == UIGestureRecognizerStateBegan) {
        // Remover UITextView e terminar edição se estiver ativa
        UITextView *textView = [noteView viewWithTag:3002];
        if (textView) {
            // Fechar teclado
            [textView resignFirstResponder];

            // Verificar se o texto mudou
            NSAttributedString *originalText = objc_getAssociatedObject(textView, "originalText");
            NSString *newPlainText = textView.text;
            NSString *originalPlainText = originalText.string;

            if (![newPlainText isEqualToString:originalPlainText]) {
                // Texto mudou - criar novo attributedString com estilo original
                NSLog(@"📝 Texto editado durante resize - plain text: %@", newPlainText);

                // Pegar atributos da primeira linha do texto original
                NSDictionary *baseAttributes = [originalText attributesAtIndex:0 effectiveRange:NULL];
                NSAttributedString *newAttributedText = [[NSAttributedString alloc] initWithString:newPlainText attributes:baseAttributes];

                // Guardar o novo texto editado
                objc_setAssociatedObject(noteView, "attributedText", newAttributedText, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

                // Atualizar CATextLayer
                for (CALayer *sublayer in noteView.layer.sublayers) {
                    if ([sublayer isKindOfClass:[CATextLayer class]]) {
                        CATextLayer *textLayer = (CATextLayer *)sublayer;
                        textLayer.string = newAttributedText;
                        break;
                    }
                }

                // TODO: Notificar JavaScript sobre a mudança de texto
            }

            // Remover UITextView
            [textView removeFromSuperview];
        }

        // Desabilitar pan gesture do container (arrastar nota)
        for (UIGestureRecognizer *gesture in container.gestureRecognizers) {
            if ([gesture isKindOfClass:[UIPanGestureRecognizer class]] && gesture != recognizer) {
                gesture.enabled = NO;
            }
        }

        // Desabilitar scroll da página enquanto redimensiona
        for (UIView *subview in _pdfView.subviews) {
            if ([subview isKindOfClass:[UIScrollView class]]) {
                UIScrollView *scrollView = (UIScrollView *)subview;
                scrollView.scrollEnabled = NO;
            }
        }
    }

    if (recognizer.state == UIGestureRecognizerStateBegan || recognizer.state == UIGestureRecognizerStateChanged) {
        CGPoint translation = [recognizer translationInView:container];
        CGRect currentNoteFrame = noteView.frame;
        CGRect newNoteFrame = currentNoteFrame;

        // Dimensões atuais da nota (sem o +6)
        CGFloat currentWidth = currentNoteFrame.size.width - 6;
        CGFloat currentHeight = currentNoteFrame.size.height - 6;

        // Variável para controlar movimento do container
        CGFloat containerDeltaY = 0;

        // Aplicar transformação baseado no botão
        switch (resizeButton.tag) {
            case 4001: // TOP MIDDLE - redimensionar altura para cima (move topo, fundo fixo)
                // Nota mantém posição dentro do container, apenas muda height
                newNoteFrame.size.height = currentHeight - translation.y + 6;
                // Container move-se para compensar
                containerDeltaY = translation.y;
                break;

            case 4002: // TOP RIGHT - redimensionar para cima/direita (move topo, fundo e esquerda fixos)
                // Nota mantém posição dentro do container, muda width e height
                newNoteFrame.size.width = currentWidth + translation.x + 6;
                newNoteFrame.size.height = currentHeight - translation.y + 6;
                // Container move-se para compensar
                containerDeltaY = translation.y;
                break;

            case 4003: // MIDDLE RIGHT - redimensionar largura (mantendo esquerda fixa)
                newNoteFrame.size.width = currentWidth + translation.x + 6;
                break;

            case 4004: // BOTTOM RIGHT - redimensionar para baixo/direita (canto superior esquerdo fixo)
                newNoteFrame.size.width = currentWidth + translation.x + 6;
                newNoteFrame.size.height = currentHeight + translation.y + 6;
                break;

            case 4005: // BOTTOM MIDDLE - redimensionar altura para baixo (topo fixo)
                newNoteFrame.size.height = currentHeight + translation.y + 6;
                break;
        }

        // Aplicar limitações de tamanho mínimo
        if (newNoteFrame.size.width < minNoteWidth + 6) {
            newNoteFrame.size.width = minNoteWidth + 6;
        }
        if (newNoteFrame.size.height < minNoteHeight + 6) {
            newNoteFrame.size.height = minNoteHeight + 6;
        }

        // APLICAR o novo frame ao noteView
        noteView.frame = newNoteFrame;

        // Atualizar borda de seleção
        if (selectionBorder) {
            CGRect borderFrame = CGRectMake(newNoteFrame.origin.x - borderOffset,
                                           newNoteFrame.origin.y - borderOffset,
                                           newNoteFrame.size.width + (borderOffset * 2),
                                           newNoteFrame.size.height + (borderOffset * 2));
            selectionBorder.frame = borderFrame;

            // Recriar path da borda
            for (CALayer *layer in [selectionBorder.layer.sublayers copy]) {
                if ([layer isKindOfClass:[CAShapeLayer class]]) {
                    [layer removeFromSuperlayer];
                }
            }

            CAShapeLayer *dottedBorder = [CAShapeLayer layer];
            dottedBorder.strokeColor = [UIColor colorWithRed:0.2 green:0.4 blue:0.8 alpha:1.0].CGColor;
            dottedBorder.fillColor = nil;
            dottedBorder.lineDashPattern = @[@4, @4];
            dottedBorder.lineWidth = 2.0;
            dottedBorder.frame = selectionBorder.bounds;

            UIBezierPath *borderPath = [UIBezierPath bezierPath];
            CGRect bounds = selectionBorder.bounds;
            [borderPath moveToPoint:CGPointMake(0, 0)];
            [borderPath addLineToPoint:CGPointMake(bounds.size.width, 0)];
            [borderPath addLineToPoint:CGPointMake(bounds.size.width, bounds.size.height)];
            [borderPath addLineToPoint:CGPointMake(0, bounds.size.height)];

            dottedBorder.path = borderPath.CGPath;
            [selectionBorder.layer addSublayer:dottedBorder];
        }

        // Atualizar posições dos botões de resize
        UIView *topMid = [container viewWithTag:4001];
        UIView *topRight = [container viewWithTag:4002];
        UIView *midRight = [container viewWithTag:4003];
        UIView *bottomRight = [container viewWithTag:4004];
        UIView *bottomMid = [container viewWithTag:4005];

        if (topMid) topMid.frame = CGRectMake(newNoteFrame.origin.x + newNoteFrame.size.width/2 - btnSize/2,
                                               newNoteFrame.origin.y - borderOffset - btnSize/2,
                                               btnSize, btnSize);

        if (topRight) topRight.frame = CGRectMake(newNoteFrame.origin.x + newNoteFrame.size.width + borderOffset - btnSize/2,
                                                   newNoteFrame.origin.y - borderOffset - btnSize/2,
                                                   btnSize, btnSize);

        if (midRight) midRight.frame = CGRectMake(newNoteFrame.origin.x + newNoteFrame.size.width + borderOffset - btnSize/2,
                                                   newNoteFrame.origin.y + newNoteFrame.size.height/2 - btnSize/2,
                                                   btnSize, btnSize);

        if (bottomRight) bottomRight.frame = CGRectMake(newNoteFrame.origin.x + newNoteFrame.size.width + borderOffset - btnSize/2,
                                                         newNoteFrame.origin.y + newNoteFrame.size.height + borderOffset - btnSize/2,
                                                         btnSize, btnSize);

        if (bottomMid) bottomMid.frame = CGRectMake(newNoteFrame.origin.x + newNoteFrame.size.width/2 - btnSize/2,
                                                     newNoteFrame.origin.y + newNoteFrame.size.height + borderOffset - btnSize/2,
                                                     btnSize, btnSize);

        // Atualizar sideView
        if (sideView) {
            CGFloat sideViewWidth = leftMargin - borderOffset;
            sideView.frame = CGRectMake(0,
                                       newNoteFrame.origin.y - borderOffset,
                                       sideViewWidth,
                                       newNoteFrame.size.height + (borderOffset * 2));

            // Atualizar ícone de arrastar
            for (UIView *subview in [sideView.subviews copy]) {
                [subview removeFromSuperview];
            }

            CGFloat sideViewHeight = newNoteFrame.size.height + (borderOffset * 2);
            CGFloat iconWidth = sideViewWidth * 0.5;
            CGFloat iconX = (sideViewWidth - iconWidth) / 2;

            for (int i = 0; i < 3; i++) {
                UIView *line = [[UIView alloc] initWithFrame:CGRectMake(iconX, sideViewHeight/2 - 6 + i*5, iconWidth, 2)];
                line.backgroundColor = [UIColor whiteColor];
                line.layer.cornerRadius = 1.0;
                [sideView addSubview:line];
            }
        }

        // Atualizar frame do container (tamanho e posição)
        CGFloat containerWidth = newNoteFrame.size.width + leftMargin + rightMargin;
        CGFloat containerHeight = newNoteFrame.size.height + topMargin + bottomMargin;
        CGRect containerFrame = container.frame;
        containerFrame.origin.y += containerDeltaY; // Ajustar Y quando botões de topo são usados
        containerFrame.size = CGSizeMake(containerWidth, containerHeight);
        container.frame = containerFrame;

        [recognizer setTranslation:CGPointZero inView:container];
        
        
        // Atualizar textLayer quando o resize terminar (sem animação)
        CGFloat textPadding = noteView.layer.borderWidth + 2;
        CGRect finalTextFrame = CGRectMake(textPadding, textPadding,
                                          noteView.frame.size.width - (textPadding * 2),
                                          noteView.frame.size.height - (textPadding * 2));

        [CATransaction begin];
        [CATransaction setDisableActions:YES];

        for (CALayer *sublayer in noteView.layer.sublayers) {
            if ([sublayer isKindOfClass:[CATextLayer class]]) {
                sublayer.frame = finalTextFrame;
                break;
            }
        }

        [CATransaction commit];

    } else if (recognizer.state == UIGestureRecognizerStateEnded || recognizer.state == UIGestureRecognizerStateCancelled) {
        // Reabilitar pan gesture do container (arrastar nota)
        for (UIGestureRecognizer *gesture in container.gestureRecognizers) {
            if ([gesture isKindOfClass:[UIPanGestureRecognizer class]] && gesture != recognizer) {
                gesture.enabled = YES;
            }
        }

        // Reabilitar scroll da página
        if (_scrollEnabled) {
            for (UIView *subview in _pdfView.subviews) {
                if ([subview isKindOfClass:[UIScrollView class]]) {
                    UIScrollView *scrollView = (UIScrollView *)subview;
                    scrollView.scrollEnabled = YES;
                }
            }
        }

        // Calcular posição e dimensões em percentagem para notificar JavaScript
        NSString *noteId = container.accessibilityIdentifier ?: @"note";
        PDFPage *page = [_pdfDocument pageAtIndex:0];
        if (page) {
            CGRect pageBounds = [page boundsForBox:kPDFDisplayBoxCropBox];

            // Converter canto superior esquerdo da nota real para coordenadas da página
            CGPoint topLeft = [container convertPoint:noteView.frame.origin toView:container.superview];

            // Dimensões da nota (remover +6 e borderWidth*2)
            CGFloat currentScale = _scale > 0 ? _scale : 1.0;
            CGFloat adjustedBorderWidth = noteView.layer.borderWidth * currentScale; // Converter de volta para tamanho original
            CGFloat noteWidth = noteView.frame.size.width - 6 - (adjustedBorderWidth * 2);
            CGFloat noteHeight = noteView.frame.size.height - 6 - (adjustedBorderWidth * 2);

            // Converter para percentagens
            CGFloat xPercent = (topLeft.x / pageBounds.size.width) * 100.0;
            CGFloat yPercent = (topLeft.y / pageBounds.size.height) * 100.0;
            CGFloat widthPercent = (noteWidth / pageBounds.size.width) * 100.0;
            CGFloat heightPercent = (noteHeight / pageBounds.size.height) * 100.0;

            NSLog(@"📐 Nota redimensionada: ID=%@, x=%.2f%%, y=%.2f%%, width=%.2f%%, height=%.2f%%",
                  noteId, xPercent, yPercent, widthPercent, heightPercent);

            // Notificar JavaScript sobre a nova posição e tamanho
            [self notifyOnChangeWithMessage:[[NSString alloc] initWithString:[NSString stringWithFormat:@"noteMoved|%@|%f|%f|%f|%f",
                noteId, xPercent, yPercent, widthPercent, heightPercent]]];
        }
    }
}

// Remover overlays com tags específicas
- (void)removeOverlaysWithTags:(NSArray<NSNumber *> *)tags
{
    dispatch_async(dispatch_get_main_queue(), ^{
        NSInteger removedCount = 0;
        for (UIView *subview in self->_pdfView.subviews) {
            if ([subview isKindOfClass:[UIScrollView class]]) {
                UIScrollView *scrollView = (UIScrollView *)subview;

                // Iterar pelas pageViews dentro do scrollView
                for (UIView *pageView in scrollView.subviews) {
                    NSMutableArray *viewsToRemove = [NSMutableArray array];
                    for (UIView *view in pageView.subviews) {
                        if ([tags containsObject:@(view.tag)]) {
                            [viewsToRemove addObject:view];
                        }
                    }

                    // Remover todas as views encontradas
                    for (UIView *view in viewsToRemove) {
                        [view removeFromSuperview];
                        removedCount++;
                    }
                }
            }
        }
    });
}

// Ajustar borderWidth das notas de texto para compensar o zoom
- (void)adjustTextNotesBorderWidth {
    CGFloat currentScale = _scale > 0 ? _scale : 1.0;

    for (UIView *subview in _pdfView.subviews) {
        if ([subview isKindOfClass:[UIScrollView class]]) {
            UIScrollView *scrollView = (UIScrollView *)subview;
            for (UIView *pageView in scrollView.subviews) {
                for (UIView *view in pageView.subviews) {
                    if (view.tag == 3000) { // Container de nota de texto
                        UIView *noteView = [view viewWithTag:3001];
                        if (noteView) {
                            // Recuperar borderWidth original
                            NSNumber *originalBorderWidth = objc_getAssociatedObject(noteView, "originalBorderWidth");
                            if (originalBorderWidth) {
                                // Ajustar borderWidth inversamente proporcional ao scale
                                CGFloat adjustedBorderWidth = [originalBorderWidth floatValue] / currentScale;
                                noteView.layer.borderWidth = adjustedBorderWidth;

                                // Ajustar textFrame: o que o borderWidth perde, o texto ganha
                                CGFloat textPadding = adjustedBorderWidth + 2;
                                CGRect newTextFrame = CGRectMake(textPadding, textPadding,
                                                                noteView.bounds.size.width - (textPadding * 2),
                                                                noteView.bounds.size.height - (textPadding * 2));

                                // Atualizar CATextLayer
                                for (CALayer *sublayer in noteView.layer.sublayers) {
                                    if ([sublayer isKindOfClass:[CATextLayer class]]) {
                                        sublayer.frame = newTextFrame;
                                        break;
                                    }
                                }

                                // Atualizar UITextView se existir
                                UITextView *textView = [noteView viewWithTag:3002];
                                if (textView) {
                                    textView.frame = newTextFrame;
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

#pragma mark - UITextViewDelegate

- (void)textViewDidChange:(UITextView *)textView {
    // Atualizar CATextLayer em tempo real enquanto edita
    if (textView.tag != 3002) return;

    // Encontrar o noteView pai
    UIView *noteView = textView.superview;
    if (!noteView || noteView.tag != 3001) return;

    // Obter o texto original para pegar os atributos de estilo
    NSAttributedString *originalText = objc_getAssociatedObject(textView, "originalText");
    if (!originalText) return;

    // Criar novo attributed string com o texto editado mas mantendo estilo base
    NSString *newPlainText = textView.text;

    // Pegar os atributos da primeira linha do texto original (mantém fonte, cor, opacidade)
    NSDictionary *baseAttributes = [originalText attributesAtIndex:0 effectiveRange:NULL];
    NSMutableDictionary *attributes = [baseAttributes mutableCopy];

    // Garantir que mantém a cor original (não transparente) para o CATextLayer
    // Os atributos já incluem NSForegroundColorAttributeName com cor e opacidade originais
    // Apenas garantir que existe
    if (!attributes[NSForegroundColorAttributeName]) {
        // Fallback se não existir cor
        attributes[NSForegroundColorAttributeName] = [UIColor blackColor];
    }

    NSAttributedString *newAttributedText = [[NSAttributedString alloc] initWithString:newPlainText attributes:attributes];

    // Atualizar CATextLayer
    for (CALayer *sublayer in noteView.layer.sublayers) {
        if ([sublayer isKindOfClass:[CATextLayer class]]) {
            CATextLayer *textLayer = (CATextLayer *)sublayer;
            textLayer.string = newAttributedText;
            break;
        }
    }

    // Manter o texto da UITextView transparente
    NSMutableAttributedString *transparentText = [[NSMutableAttributedString alloc] initWithString:newPlainText attributes:attributes];
    [transparentText addAttribute:NSForegroundColorAttributeName
                            value:[UIColor clearColor]
                            range:NSMakeRange(0, transparentText.length)];

    // Guardar a posição do cursor
    NSRange selectedRange = textView.selectedRange;

    // Atualizar UITextView com texto transparente
    textView.attributedText = transparentText;

    // Restaurar posição do cursor
    textView.selectedRange = selectedRange;
}

@end

#ifdef RCT_NEW_ARCH_ENABLED
Class<RCTComponentViewProtocol> RNPDFPdfViewCls(void)
{
    return RNPDFPdfView.class;
}

#endif
