package clay

import "core:c"

when ODIN_OS == .Windows {
    foreign import Clay "windows/clay.lib"
} else when ODIN_OS == .Linux {
    foreign import Clay "linux/clay.a"
} else when ODIN_OS == .Darwin {
    when ODIN_ARCH == .arm64 {
        foreign import Clay "macos-arm64/clay.a"
    } else {
        foreign import Clay "macos/clay.a"
    }
} else when ODIN_ARCH == .wasm32 || ODIN_ARCH == .wasm64p32 {
    foreign import Clay "wasm/clay.o"
}

String :: struct {
    isStaticallyAllocated: c.bool,
    length: c.int32_t,
    chars:  [^]c.char,
}

StringSlice :: struct {
    length:    c.int32_t,
    chars:     [^]c.char,
    baseChars: [^]c.char,
}

Vector2 :: [2]c.float

Dimensions :: struct {
    width:  c.float,
    height: c.float,
}

Arena :: struct {
    nextAllocation: uintptr,
    capacity:       c.size_t,
    memory:         [^]c.char,
}

BoundingBox :: struct {
    x:      c.float,
    y:      c.float,
    width:  c.float,
    height: c.float,
}

Color :: [4]c.float   // RGBA, 0–255 range as floats

CornerRadius :: struct {
    topLeft:     c.float,
    topRight:    c.float,
    bottomLeft:  c.float,
    bottomRight: c.float,
}

BorderData :: struct {
    width: u32,
    color: Color,
}

ElementId :: struct {
    id:       u32,
    offset:   u32,
    baseId:   u32,
    stringId: String,
}

when ODIN_OS == .Windows {
    EnumBackingType :: u32
} else {
    EnumBackingType :: u8
}

RenderCommandType :: enum EnumBackingType {
    None,
    Rectangle,
    Border,
    Text,
    Image,
    ScissorStart,
    ScissorEnd,
    Custom,
}

TextWrapMode :: enum EnumBackingType {
    Words,
    Newlines,
    None,
}

TextAlignment :: enum EnumBackingType {
    Left,
    Center,
    Right,
}

TextElementConfig :: struct {
    userData:      rawptr,
    textColor:     Color,
    fontId:        u16,
    fontSize:      u16,
    letterSpacing: u16,
    lineHeight:    u16,
    wrapMode:      TextWrapMode,
    textAlignment: TextAlignment,
}

AspectRatioElementConfig :: struct {
    aspectRatio: f32,
}

ImageElementConfig :: struct {
    imageData: rawptr,
}

CustomElementConfig :: struct {
    customData: rawptr,
}

BorderWidth :: struct {
    left:            u16,
    right:           u16,
    top:             u16,
    bottom:          u16,
    betweenChildren: u16,
}

BorderElementConfig :: struct {
    color: Color,
    width: BorderWidth,
}

ClipElementConfig :: struct {
    horizontal:  bool,
    vertical:    bool,
    childOffset: Vector2,
}

FloatingAttachPointType :: enum EnumBackingType {
    LeftTop, LeftCenter, LeftBottom,
    CenterTop, CenterCenter, CenterBottom,
    RightTop, RightCenter, RightBottom,
}

FloatingAttachPoints :: struct {
    element: FloatingAttachPointType,
    parent:  FloatingAttachPointType,
}

PointerCaptureMode :: enum EnumBackingType {
    Capture,
    Passthrough,
}

FloatingAttachToElement :: enum EnumBackingType {
    None, Parent, ElementWithId, Root,
}

FloatingClipToElement :: enum EnumBackingType {
    None, AttachedParent,
}

FloatingElementConfig :: struct {
    offset:             Vector2,
    expand:             Dimensions,
    parentId:           u32,
    zIndex:             i16,
    attachment:         FloatingAttachPoints,
    pointerCaptureMode: PointerCaptureMode,
    attachTo:           FloatingAttachToElement,
    clipTo:             FloatingClipToElement,
}

TextRenderData :: struct {
    stringContents: StringSlice,
    textColor:      Color,
    fontId:         u16,
    fontSize:       u16,
    letterSpacing:  u16,
    lineHeight:     u16,
}

RectangleRenderData :: struct {
    backgroundColor: Color,
    cornerRadius:    CornerRadius,
}

ImageRenderData :: struct {
    backgroundColor: Color,
    cornerRadius:    CornerRadius,
    imageData:       rawptr,
}

CustomRenderData :: struct {
    backgroundColor: Color,
    cornerRadius:    CornerRadius,
    customData:      rawptr,
}

BorderRenderData :: struct {
    color:        Color,
    cornerRadius: CornerRadius,
    width:        BorderWidth,
}

RenderCommandData :: struct #raw_union {
    rectangle: RectangleRenderData,
    text:      TextRenderData,
    image:     ImageRenderData,
    custom:    CustomRenderData,
    border:    BorderRenderData,
}

RenderCommand :: struct {
    boundingBox:  BoundingBox,
    renderData:   RenderCommandData,
    userData:     rawptr,
    id:           u32,
    zIndex:       i16,
    commandType:  RenderCommandType,
}

ScrollContainerData :: struct {
    scrollPosition:            ^Vector2,
    scrollContainerDimensions: Dimensions,
    contentDimensions:         Dimensions,
    config:                    ClipElementConfig,
    found:                     bool,
}

ElementData :: struct {
    boundingBox: BoundingBox,
    found:       bool,
}

PointerDataInteractionState :: enum EnumBackingType {
    PressedThisFrame,
    Pressed,
    ReleasedThisFrame,
    Released,
}

PointerData :: struct {
    position: Vector2,
    state:    PointerDataInteractionState,
}

SizingType :: enum EnumBackingType {
    Fit, Grow, Percent, Fixed,
}

SizingConstraintsMinMax :: struct {
    min: c.float,
    max: c.float,
}

SizingConstraints :: struct #raw_union {
    sizeMinMax:  SizingConstraintsMinMax,
    sizePercent: c.float,
}

SizingAxis :: struct {
    constraints: SizingConstraints,
    type:        SizingType,
}

Sizing :: struct {
    width:  SizingAxis,
    height: SizingAxis,
}

Padding :: struct {
    left:   u16,
    right:  u16,
    top:    u16,
    bottom: u16,
}

LayoutDirection :: enum EnumBackingType {
    LeftToRight,
    TopToBottom,
}

LayoutAlignmentX :: enum EnumBackingType {
    Left, Right, Center,
}

LayoutAlignmentY :: enum EnumBackingType {
    Top, Bottom, Center,
}

ChildAlignment :: struct {
    x: LayoutAlignmentX,
    y: LayoutAlignmentY,
}

LayoutConfig :: struct {
    sizing:          Sizing,
    padding:         Padding,
    childGap:        u16,
    childAlignment:  ChildAlignment,
    layoutDirection: LayoutDirection,
}

ClayArray :: struct($type: typeid) {
    capacity:      i32,
    length:        i32,
    internalArray: [^]type,
}

ElementDeclaration :: struct {
    layout:          LayoutConfig,
    backgroundColor: Color,
    cornerRadius:    CornerRadius,
    aspectRatio:     AspectRatioElementConfig,
    image:           ImageElementConfig,
    floating:        FloatingElementConfig,
    custom:          CustomElementConfig,
    clip:            ClipElementConfig,
    border:          BorderElementConfig,
    userData:        rawptr,
}

ErrorType :: enum EnumBackingType {
    TextMeasurementFunctionNotProvided,
    ArenaCapacityExceeded,
    ElementsCapacityExceeded,
    TextMeasurementCapacityExceeded,
    DuplicateId,
    FloatingContainerParentNotFound,
    PercentageOver1,
    InternalError,
}

ErrorData :: struct {
    errorType: ErrorType,
    errorText: String,
    userData:  rawptr,
}

ErrorHandler :: struct {
    handler:  proc "c" (errorData: ErrorData),
    userData: rawptr,
}

Context :: struct {}

@(link_prefix = "Clay_", default_calling_convention = "c")
foreign Clay {
    _OpenElement         :: proc() ---
    _OpenElementWithId   :: proc(id: ElementId) ---
    _CloseElement        :: proc() ---
    MinMemorySize        :: proc() -> u32 ---
    CreateArenaWithCapacityAndMemory :: proc(capacity: c.size_t, offset: [^]u8) -> Arena ---
    SetPointerState      :: proc(position: Vector2, pointerDown: bool) ---
    Initialize           :: proc(arena: Arena, layoutDimensions: Dimensions, errorHandler: ErrorHandler) -> ^Context ---
    GetCurrentContext    :: proc() -> ^Context ---
    SetCurrentContext    :: proc(ctx: ^Context) ---
    UpdateScrollContainers :: proc(enableDragScrolling: bool, scrollDelta: Vector2, deltaTime: c.float) ---
    SetLayoutDimensions  :: proc(dimensions: Dimensions) ---
    BeginLayout          :: proc() ---
    EndLayout            :: proc() -> ClayArray(RenderCommand) ---
    GetElementId         :: proc(id: String) -> ElementId ---
    GetElementIdWithIndex :: proc(id: String, index: u32) -> ElementId ---
    GetElementData       :: proc(id: ElementId) -> ElementData ---
    Hovered              :: proc() -> bool ---
    OnHover              :: proc(onHoverFunction: proc "c" (id: ElementId, pointerData: PointerData, userData: rawptr), userData: rawptr) ---
    PointerOver          :: proc(id: ElementId) -> bool ---
    GetScrollOffset      :: proc() -> Vector2 ---
    GetScrollContainerData :: proc(id: ElementId) -> ScrollContainerData ---
    SetMeasureTextFunction :: proc(measureTextFunction: proc "c" (text: StringSlice, config: ^TextElementConfig, userData: rawptr) -> Dimensions, userData: rawptr) ---
    SetQueryScrollOffsetFunction :: proc(queryScrollOffsetFunction: proc "c" (elementId: u32, userData: rawptr) -> Vector2, userData: rawptr) ---
    RenderCommandArray_Get :: proc(array: ^ClayArray(RenderCommand), index: i32) -> ^RenderCommand ---
    SetDebugModeEnabled  :: proc(enabled: bool) ---
    IsDebugModeEnabled   :: proc() -> bool ---
    SetCullingEnabled    :: proc(enabled: bool) ---
    GetMaxElementCount   :: proc() -> i32 ---
    SetMaxElementCount   :: proc(maxElementCount: i32) ---
    GetMaxMeasureTextCacheWordCount :: proc() -> i32 ---
    SetMaxMeasureTextCacheWordCount :: proc(maxMeasureTextCacheWordCount: i32) ---
    ResetMeasureTextCache :: proc() ---
}

@(link_prefix = "Clay_", default_calling_convention = "c", private)
foreign Clay {
    _ConfigureOpenElement :: proc(config: ElementDeclaration) ---
    _HashString           :: proc(key: String, seed: u32) -> ElementId ---
    _HashStringWithOffset :: proc(key: String, index: u32, seed: u32) -> ElementId ---
    _OpenTextElement      :: proc(text: String, textConfig: ^TextElementConfig) ---
    _StoreTextElementConfig :: proc(config: TextElementConfig) -> ^TextElementConfig ---
    _GetParentElementId   :: proc() -> u32 ---
}

// ---------------------------------------------------------------------------
// Odin-side helpers
// ---------------------------------------------------------------------------

ConfigureOpenElement :: proc(config: ElementDeclaration) -> bool {
    _ConfigureOpenElement(config)
    return true
}

@(deferred_none = _CloseElement)
UI_WithId :: proc(id: ElementId) -> proc(config: ElementDeclaration) -> bool {
    _OpenElementWithId(id)
    return ConfigureOpenElement
}

@(deferred_none = _CloseElement)
UI_AutoId :: proc() -> proc(config: ElementDeclaration) -> bool {
    _OpenElement()
    return ConfigureOpenElement
}

UI :: proc{UI_WithId, UI_AutoId}

Text :: proc($text: string, config: ^TextElementConfig) {
    wrapped := MakeString(text)
    wrapped.isStaticallyAllocated = true
    _OpenTextElement(wrapped, config)
}

TextDynamic :: proc(text: string, config: ^TextElementConfig) {
    _OpenTextElement(MakeString(text), config)
}

TextConfig :: proc(config: TextElementConfig) -> ^TextElementConfig {
    return _StoreTextElementConfig(config)
}

PaddingAll :: proc(p: u16) -> Padding {
    return { left = p, right = p, top = p, bottom = p }
}

CornerRadiusAll :: proc(radius: f32) -> CornerRadius {
    return { radius, radius, radius, radius }
}

SizingFit :: proc(sizeMinMax: SizingConstraintsMinMax = {}) -> SizingAxis {
    return SizingAxis{ type = .Fit, constraints = { sizeMinMax = sizeMinMax } }
}

SizingGrow :: proc(sizeMinMax: SizingConstraintsMinMax = {}) -> SizingAxis {
    return SizingAxis{ type = .Grow, constraints = { sizeMinMax = sizeMinMax } }
}

SizingFixed :: proc(size: c.float) -> SizingAxis {
    return SizingAxis{ type = .Fixed, constraints = { sizeMinMax = { size, size } } }
}

SizingPercent :: proc(pct: c.float) -> SizingAxis {
    return SizingAxis{ type = .Percent, constraints = { sizePercent = pct } }
}

MakeString :: proc(label: string) -> String {
    return String{ chars = raw_data(label), length = cast(c.int)len(label) }
}

ID :: proc(label: string, index: u32 = 0) -> ElementId {
    return _HashString(MakeString(label), index)
}

ID_LOCAL :: proc(label: string, index: u32 = 0) -> ElementId {
    return _HashStringWithOffset(MakeString(label), index, _GetParentElementId())
}
