I researched the Tiger-era iChat UI, its historical design origins, and the GNUstep drawing/text APIs. The important finding is that the “Aqua bubble” effect was **not fundamentally a special chat-widget primitive**: it was a custom transcript renderer built around ordinary text layout and carefully drawn bubble graphics.

# Reconstructing the Mac OS X 10.4 iChat Aqua Chat Bubbles with GNUstep

## 1. Executive summary

Mac OS X 10.4 Tiger shipped with **iChat 3.0**. Its text-chat window presented a conversation as graphical speech balloons rather than a conventional text log. Messages were visually associated with the speaker's buddy picture, with the two participants occupying opposite sides of the transcript. While one participant was typing, iChat displayed a small “thought” or cloud bubble beside that participant's picture.

Apple's original description explicitly called these **“dialogue bubbles”** and said that iChat used them together with buddy photos to present instant messages “in a graphically conversational manner.” ([Apple][1])

The design goes back considerably further than Tiger. Former Apple engineer Jens Alfke published his original **April 21, 1997** sketch for a speech-balloon chat interface. He identifies several ideas that survived into iChat:

* speech balloons;
* per-speaker colorization;
* placing one's own messages on the opposite side from everybody else;
* changing text alignment and balloon margins to reinforce that distinction;
* a temporary typing indicator represented by a dotted/thought bubble;
* user pictures.

He also specifically says that the iChat implementation used **NSTextView-based balloons**. ([Thought Palace][2])

That is the key implementation clue for a GNUstep recreation.

The recommended GNUstep architecture is therefore:

**conversation model → bubble layout → custom bubble drawing → GNUstep text layout/rendering**

rather than trying to turn ordinary `NSTextField`s into rounded controls.

---

## 2. What the Tiger chat window actually did

Historical documentation for Tiger describes the interaction quite clearly.

When a text chat was started, the window contained a transcript area and an input field at the bottom. As the local user typed, a small cloud appeared beside their picture. When the message was sent, the message appeared in the transcript beside their icon. Incoming messages appeared beside the other participant's icon, and the cloud likewise appeared beside that participant while they were typing. ([Flylib][3])

The visual design can therefore be thought of as four related objects:

```text
                 transcript
    ┌───────────────────────────────────┐
    │                                   │
    │  [buddy]  ╭──────────────╮        │
    │           │ Hello there  │        │
    │           ╰──────────────╯        │
    │                                   │
    │              ╭──────────────╮ [me]│
    │              │ Hi!           │     │
    │              ╰──────────────╯     │
    │                                   │
    │  [buddy]  ( · · · )               │
    │            typing indicator       │
    │                                   │
    ├───────────────────────────────────┤
    │             input field           │
    └───────────────────────────────────┘
```

The important visual properties were:

1. **Speaker identity was spatial.**
   The remote participant occupied one side and the local participant the other.

2. **Color was associated with speaker identity.**
   iChat supported user-selectable bubble and font colors. Historical iChat documentation confirms that the Messages preferences allowed the user to choose the outgoing bubble color, font, font style, and font color. ([ralphjohns.co.uk][4])

3. **The balloon was content-sized.**
   Short messages produced small pills; longer messages expanded vertically and wrapped.

4. **The buddy picture lived in the margin.**
   The picture was not simply embedded in the bubble.

5. **Typing was a different visual state.**
   A little cloud indicated that something was being composed but not yet sent. ([Flylib][3])

6. **The transcript was a scrolling document.**
   It was not merely a collection of independent buttons.

---

## 3. The design was deliberately asymmetric

The most important visual trick is not the gradient.

It is **alignment**.

Jens Alfke's historical account says that iChat put the user's messages on the opposite side from everyone else's, and that the text alignment and outer margins were also changed to make the distinction more obvious. ([Thought Palace][2])

A faithful implementation should consequently use something like:

```text
incoming:

avatar ┃  ╭──────────────────╮
       ┃  │ Message from Bob │
       ┃  ╰──────────────────╯


outgoing:

                    ╭──────────────────╮  ┃ avatar
                    │ Message from me │  ┃
                    ╰──────────────────╯  ┃
```

Do not merely use identical bubbles with different colors. The **geometry itself communicates authorship**.

---

## 4. What “Aqua” means here

The Aqua character came from several subtle effects rather than one magic gradient.

Apple's Aqua guidelines describe the overall style as including:

* antialiased text and graphics;
* shadowing;
* transparency;
* careful use of color;
* dimensional controls and highlights. ([Scribd][5])

For the iChat balloons, the visual recipe is approximately:

```text
        light highlight
       ┌───────────────┐
       │               │
       │    message    │  ← saturated/translucent body
       │               │
       └───────────────┘
             ╲
              ╲ small tail
```

A convincing recreation needs:

* a rounded silhouette;
* a small tail;
* a thin darker edge;
* a vertically varying fill;
* a narrow top highlight;
* optional soft shadow;
* antialiased text;
* a restrained amount of translucency.

The **highlight is important**. A flat rounded rectangle with a blue/yellow fill looks much more like a modern web chat bubble than Tiger iChat.

---

## 5. An important historical implementation clue

The strongest evidence about the original implementation comes from Alfke's retrospective:

> iChat used “NSTextView-based balloons.”

He also mentions that he had considered physically connecting consecutive balloons with “pipes”, but that this proved troublesome and was not implemented in the NSTextView-based version. ([Thought Palace][2])

This suggests a useful conceptual model:

```text
                  NSTextView / text system
                           │
                  attributed message text
                           │
                     bubble geometry
                           │
                 custom background drawing
                           │
                    transcript view
```

In other words, the bubble should be treated as **decoration surrounding a normal text layout**, rather than as an image containing pre-rendered text.

That is exactly the direction GNUstep's AppKit text system makes practical.

---

# 6. GNUstep equivalents

GNUstep provides essentially all of the primitives required.

### `NSView`

A custom `NSView` can override `drawRect:` and perform arbitrary drawing in its coordinate system. ([GNUstep][6])

This is the natural base class for a transcript renderer.

### `NSBezierPath`

GNUstep supplies `NSBezierPath`, including arcs and custom path construction. It can therefore construct the rounded balloon and its tail without requiring image assets. ([GNUstep][7])

There is one compatibility detail worth noting:

`+bezierPathWithRoundedRect:xRadius:yRadius:` is documented as a Mac OS X 10.5 API. ([GNUstep][7])

Therefore, if the goal is to reproduce a **Tiger-era API style**, it is better to construct the rounded rectangle from arcs manually rather than relying on that convenience method.

### `NSAttributedString`

GNUstep supports attributed strings, allowing font, foreground color and other text attributes to travel with a message. ([GNUstep][8])

GNUstep also supplies drawing methods such as:

```objc
-drawAtPoint:
-drawInRect:
-drawWithRect:options:
```

and corresponding sizing methods. ([GNUstep][9])

### `NSTextContainer` / `NSLayoutManager`

For a more authentic implementation, use the GNUstep text system for measurement and wrapping rather than calculating string widths manually.

`NSTextContainer` defines the region in which text is laid out, while `NSLayoutManager` exposes glyph and bounding-rectangle calculations. ([GNUstep][10])

This is especially useful for:

* multi-line messages;
* different fonts;
* Unicode;
* mixed formatting;
* precise bubble sizing.

### Gradients

Modern GNUstep provides `NSGradient`, including drawing into a Bezier path. ([GNUstep][11])

However, `NSGradient` itself corresponds to a Mac OS X 10.5 API. If maximum historical portability matters, the bubble gradient can instead be generated by drawing a series of very thin horizontal translucent rectangles.

That approach is actually quite suitable for an old-school Aqua recreation.

---

# 7. Recommended GNUstep object model

A clean implementation would have approximately these objects:

```text
ChatWindowController
        │
        ├── ChatTranscriptView
        │       │
        │       ├── ChatBubbleLayout
        │       │       ├── incoming bubble
        │       │       ├── outgoing bubble
        │       │       └── typing bubble
        │       │
        │       └── avatar images
        │
        └── NSTextView
                input field
```

The transcript itself can remain a single custom view.

Each message should be represented by a model object:

```objc
@interface ChatMessage : NSObject

@property (copy) NSString *text;
@property (copy) NSString *senderName;
@property (assign) BOOL outgoing;
@property (retain) NSAttributedString *attributedText;

@end
```

The view then converts each message into a layout rectangle.

---

# 8. Bubble layout algorithm

For each message:

### Step 1 — choose the text width

For example:

```text
transcript width = 500
avatar margin    = 48
bubble maximum   = 330
```

The bubble should not be allowed to consume the entire transcript width.

### Step 2 — measure the attributed string

Use the text system to determine the height required for the selected width.

Conceptually:

```text
message text
     ↓
attributed string
     ↓
text container, width = 300
     ↓
layout manager
     ↓
text height = 42 px
```

### Step 3 — add bubble padding

For example:

```text
left/right padding = 10
top/bottom padding = 6

bubble width  = text width + 20
bubble height = text height + 12
```

### Step 4 — reserve avatar space

Incoming:

```text
| avatar | bubble---------------- |
```

Outgoing:

```text
| ---------------- bubble | avatar |
```

### Step 5 — place the next message below it

Use a small vertical gap, with a smaller gap between consecutive messages from the same person.

This produces the characteristic conversational rhythm without needing a table view.

---

# 9. Constructing the bubble path

For maximum GNUstep/OpenStep compatibility, construct the rounded rectangle yourself.

A bubble can be made from:

1. a rounded rectangle;
2. one small triangular/curved tail;
3. a stroke.

Conceptually:

```text
      ╭────────────────────╮
     ╱                      ╲
    │                        │
    │                        │
     ╲______________________╱
                 ╲
                  ╲
```

For an incoming bubble, put the tail on the left.

For an outgoing bubble, put it on the right.

Use `NSBezierPath`'s arc methods to build the corners. Those arc primitives are part of the older OpenStep API, unlike the convenient rounded-rectangle constructor. ([GNUstep][7])

---

# 10. Example GNUstep bubble renderer

The following is the essential drawing technique. It deliberately avoids `NSGradient` and `bezierPathWithRoundedRect:` so that the interesting parts do not depend on APIs introduced after the Tiger era.

```objc
#import <AppKit/AppKit.h>

@interface AquaBubbleView : NSView
@property (retain) NSAttributedString *message;
@property (assign) BOOL outgoing;
@end

@implementation AquaBubbleView

- (NSBezierPath *)bubblePathInRect:(NSRect)r
                          outgoing:(BOOL)outgoing
{
    CGFloat radius = 11.0;
    CGFloat tail = 7.0;

    NSBezierPath *p = [NSBezierPath bezierPath];

    CGFloat left = NSMinX(r);
    CGFloat right = NSMaxX(r);
    CGFloat top = NSMaxY(r);
    CGFloat bottom = NSMinY(r);

    if (outgoing) {
        [p moveToPoint:NSMakePoint(left + radius, bottom)];

        [p lineToPoint:NSMakePoint(right - radius - tail, bottom)];
        [p appendBezierPathWithArcWithCenter:
              NSMakePoint(right - radius - tail, bottom + radius)
              radius:radius
              startAngle:270
              endAngle:360];

        [p lineToPoint:NSMakePoint(right - tail, top - radius)];
        [p appendBezierPathWithArcWithCenter:
              NSMakePoint(right - radius - tail, top - radius)
              radius:radius
              startAngle:0
              endAngle:90];

        [p lineToPoint:NSMakePoint(left + radius, top)];
        [p appendBezierPathWithArcWithCenter:
              NSMakePoint(left + radius, top - radius)
              radius:radius
              startAngle:90
              endAngle:180];

        [p lineToPoint:NSMakePoint(left, bottom + radius)];
        [p appendBezierPathWithArcWithCenter:
              NSMakePoint(left + radius, bottom + radius)
              radius:radius
              startAngle:180
              endAngle:270];

        [p closePath];

        // A simple outgoing tail.
        [p moveToPoint:NSMakePoint(right - tail - 10, bottom)];
        [p lineToPoint:NSMakePoint(right - tail, bottom)];
        [p lineToPoint:NSMakePoint(right - tail, bottom + 7)];
        [p closePath];
    } else {
        [p moveToPoint:NSMakePoint(left + radius + tail, bottom)];

        [p lineToPoint:NSMakePoint(right - radius, bottom)];
        [p appendBezierPathWithArcWithCenter:
              NSMakePoint(right - radius, bottom + radius)
              radius:radius
              startAngle:270
              endAngle:360];

        [p lineToPoint:NSMakePoint(right, top - radius)];
        [p appendBezierPathWithArcWithCenter:
              NSMakePoint(right - radius, top - radius)
              radius:radius
              startAngle:0
              endAngle:90];

        [p lineToPoint:NSMakePoint(left + radius + tail, top)];
        [p appendBezierPathWithArcWithCenter:
              NSMakePoint(left + radius + tail, top - radius)
              radius:radius
              startAngle:90
              endAngle:180];

        [p lineToPoint:NSMakePoint(left + tail, bottom + radius)];
        [p appendBezierPathWithArcWithCenter:
              NSMakePoint(left + radius + tail, bottom + radius)
              radius:radius
              startAngle:180
              endAngle:270];

        [p closePath];

        // A simple incoming tail.
        [p moveToPoint:NSMakePoint(left + tail, bottom)];
        [p lineToPoint:NSMakePoint(left + tail + 10, bottom)];
        [p lineToPoint:NSMakePoint(left + tail, bottom + 7)];
        [p closePath];
    }

    return p;
}

- (void)drawRect:(NSRect)rect
{
    NSRect bounds = [self bounds];

    NSBezierPath *bubble =
        [self bubblePathInRect:NSInsetRect(bounds, 1, 1)
                      outgoing:_outgoing];

    /*
     * Base color:
     * outgoing = warm Aqua yellow/gold
     * incoming = cool blue/purple
     *
     * These are intentionally approximations rather than claims about
     * Apple's internal color constants; iChat let users customize colors.
     */
    NSColor *base;

    if (_outgoing)
        base = [NSColor colorWithCalibratedRed:0.98
                                         green:0.77
                                          blue:0.18
                                         alpha:1.0];
    else
        base = [NSColor colorWithCalibratedRed:0.62
                                         green:0.69
                                          blue:0.82
                                         alpha:1.0];

    [base setFill];
    [bubble fill];

    /*
     * Subtle top highlight.
     * A real implementation would clip this to the bubble and use
     * a smooth alpha gradient.
     */
    [[NSColor colorWithCalibratedWhite:1.0 alpha:0.25] setFill];

    NSRect highlight = NSMakeRect(NSMinX(bounds) + 5,
                                  NSMaxY(bounds) - 8,
                                  NSWidth(bounds) - 10,
                                  3);

    NSBezierPath *highlightPath =
        [NSBezierPath bezierPathWithRect:highlight];

    [highlightPath fill];

    [[NSColor colorWithCalibratedWhite:0.15 alpha:0.25] setStroke];
    [bubble setLineWidth:1.0];
    [bubble stroke];

    /*
     * Text is rendered separately. This is important:
     * the bubble is decoration; the text remains normal Cocoa/GNUstep
     * attributed text.
     */
    if (_message) {
        NSRect textRect = NSInsetRect(bounds, 10, 6);
        [_message drawInRect:textRect];
    }
}

@end
```

The example is intentionally a **starting point**, not a claim that Apple's original source looked like this. Apple's implementation was proprietary. The historical evidence supports the architecture—speech balloons, asymmetric placement, per-speaker styling, and an NSTextView-based implementation—not Apple's private source code. ([Thought Palace][2])

---

# 11. Making the gradient look properly Aqua

The simple renderer above is still too flat.

A more convincing Aqua bubble should have a vertical color ramp:

```text
top
────────────────────
  very light
  translucent highlight

  light saturated color

  normal bubble color

  slightly darker lower edge
────────────────────
bottom
```

For GNUstep, there are two good approaches.

## Approach A — use `NSGradient`

Modern GNUstep provides `NSGradient` and can draw a gradient into a Bezier path. ([GNUstep][11])

Conceptually:

```objc
NSGradient *gradient =
    [[[NSGradient alloc]
        initWithStartingColor:topColor
        endingColor:bottomColor] autorelease];

[gradient drawInBezierPath:bubble angle:270.0];
```

This is the easiest implementation.

## Approach B — manually paint horizontal strips

For an old-style implementation, draw perhaps 32–64 horizontal strips, interpolating between the top and bottom colors.

That has two advantages:

* it does not depend on `NSGradient`;
* it gives direct control over the old Aqua aesthetic.

The result can then be clipped to the bubble path.

---

# 12. The gloss layer

The distinctive “gel” effect is best implemented as a separate layer.

Do **not** make the entire bubble semi-transparent.

Instead:

```text
bubble fill
     +
thin white translucent highlight near top
     +
dark translucent edge
     +
optional 1–2 px shadow
```

This matches the general Aqua design philosophy of antialiasing, translucency, dimensional shading and carefully controlled highlights. ([Scribd][5])

Later versions of iChat demonstrate that Apple actually kept separate graphical resources for the Balloons style. A documented example from iChat's later releases identifies `BigBubbleMask.png` and `BigBubbleGloss.png` inside `Balloons.transcriptstyle`. ([OS X Daily][12])

That is useful evidence for the visual construction even though those particular resource files are from a later iChat release rather than a verified Tiger source tree.

---

# 13. Why a custom view is preferable to `NSTextField`

A naïve implementation might create:

```text
NSTextField
    ↓
rounded background
```

for every message.

That is the wrong abstraction.

The original iChat UI is a **transcript**, and a transcript has to handle:

* arbitrary-length messages;
* wrapping;
* scrolling;
* avatars;
* typing indicators;
* multiple messages;
* different fonts;
* different colors;
* selection/copying;
* possibly links and attachments.

GNUstep's text system already supplies the difficult typography machinery. `NSTextContainer` defines the layout region and `NSLayoutManager` provides glyph/bounding information. ([GNUstep][10])

So the recommended architecture is:

```text
              ChatTranscriptView
                     │
        ┌────────────┴────────────┐
        │                         │
  bubble geometry             text system
        │                         │
  NSBezierPath             NSAttributedString
        │                         │
        └────────────┬────────────┘
                     │
                final drawing
```

---

# 14. A practical message layout structure

A useful internal structure is:

```objc
typedef struct {
    NSRect bubbleRect;
    NSRect textRect;
    NSRect avatarRect;
    BOOL outgoing;
} ChatBubbleLayout;
```

Then:

```objc
- (ChatBubbleLayout)layoutMessage:(ChatMessage *)message
                         atOrigin:(NSPoint)origin
                            width:(CGFloat)width;
```

The algorithm becomes deterministic:

```text
1. choose maximum bubble width
2. construct attributed string
3. ask text system for required height
4. add padding
5. position bubble on left/right
6. position avatar in margin
7. return rectangles
```

The drawing pass then simply renders those rectangles.

This separation is valuable because resizing the window only requires **re-layout**, not rewriting the drawing code.

---

# 15. Typing indicator

The typing indicator deserves its own bubble type.

Historical Tiger documentation calls the visual a small cloud that appears while someone is typing. ([Flylib][3])

The simplest implementation is:

```text
      ╭──────╮
     (  • • • )
      ╰──╮───╯
         │
       avatar
```

A more authentic version uses the same glossy/translucent treatment as the message balloons but contains three animated dots.

The state machine is trivial:

```text
IDLE
 │
 │ user begins typing
 ▼
TYPING
 │
 │ message sent
 ▼
IDLE
```

For the remote participant, the network protocol determines when the typing state changes.

The important visual point is that the typing bubble should **not occupy the same visual role as a sent message**. It is transient.

---

# 16. Avatars

The avatar belongs to the transcript's margin rather than inside the bubble.

For a two-person conversation:

```text
incoming:

┌────┐
│ :-)│  ╭──────────────────╮
│    │  │ Hello             │
└────┘  ╰──────────────────╯


outgoing:

                    ╭──────────────────╮  ┌────┐
                    │ Hello back       │  │ :-)│
                    ╰──────────────────╯  └────┘
```

Alfke's original design sketch also included user pictures, although he notes that the original sketch represented them simply as ovals. ([Thought Palace][2])

GNUstep's `NSImage` is sufficient for this part; its image drawing API supports compositing into the current graphics context. ([GNUstep][13])

A circular crop can be produced with a clipping path:

```objc
NSBezierPath *circle =
    [NSBezierPath bezierPathWithOvalInRect:avatarRect];

[circle addClip];

[avatar drawInRect:avatarRect];
```

Then restore the graphics state.

---

# 17. Window construction

The actual chat window can remain conventional GNUstep AppKit.

Use:

```text
NSWindow
 └── contentView
      ├── transcript NSScrollView
      │    └── ChatTranscriptView
      │
      └── input NSScrollView
           └── NSTextView
```

This mirrors the important functional structure of Tiger iChat:

* scrolling conversation;
* compose area at the bottom;
* custom rendering only where custom rendering is necessary.

GNUstep's `NSView` is explicitly designed for custom drawing through `drawRect:`. ([GNUstep][6])

---

# 18. What not to reproduce

A faithful recreation should **not** blindly reproduce every modern iMessage convention.

Tiger iChat was distinctive because it was:

* more asymmetric;
* more graphical;
* more explicitly speaker-oriented;
* less compact;
* more obviously “speech balloon” based.

Jens Alfke's account is particularly useful here: the goal was usability in multi-person conversation, not merely decorative chat bubbles. ([Thought Palace][2])

The bubble should therefore remain relatively generous and should preserve the left/right conversational structure.

---

# 19. Suggested visual constants

These are implementation recommendations, **not recovered Apple constants**:

```text
bubble corner radius       10–12 px
bubble horizontal padding  9–11 px
bubble vertical padding     5–7 px
avatar size                32–40 px
avatar-to-bubble gap        6–8 px
maximum bubble width       60–70% of transcript
message gap                 7–10 px
same-speaker gap            3–5 px
border                      1 px
highlight                   2–4 px
```

The proportions matter more than the exact numbers.

---

# 20. Color strategy

Because iChat allowed users to customize bubble and font colors, there is no single “correct” RGB value that should be treated as canonical. ([ralphjohns.co.uk][4])

For an initial Tiger-like theme, use:

```text
Outgoing:
    warm yellow/gold
    dark warm text

Incoming:
    cool blue/lavender
    dark blue-gray text

Typing:
    pale neutral/translucent gray

Border:
    darker, low-alpha version of bubble color

Highlight:
    white at roughly 15–30% opacity
```

The exact palette should be adjustable.

---

# 21. Rendering order

The correct drawing order is:

```text
1. transcript background

2. avatar shadow / avatar

3. bubble shadow

4. bubble base shape

5. bubble gradient

6. bubble edge

7. bubble gloss

8. attributed text

9. transient typing indicator
```

Graphics state should be saved/restored around each independent element.

GNUstep's `NSGraphicsContext` supports the normal graphics-state operations and compositing controls required for this type of drawing. ([GNUstep][14])

---

# 22. Recreating the old Aqua look rather than merely “rounded bubbles”

The visual hierarchy should be:

```text
                  Aqua
                    │
        ┌───────────┴───────────┐
        │                       │
     geometry                 lighting
        │                       │
   rounded path          highlight + shade
        │                       │
        └───────────┬───────────┘
                    │
                 material
                    │
             glossy colored gel
```

A modern flat UI usually does:

```text
rounded rectangle + solid fill
```

Tiger iChat should instead do:

```text
rounded path
+ tail
+ subtle gradient
+ glossy highlight
+ dark edge
+ antialiased text
+ asymmetric placement
+ avatar
```

The **combination** is what makes it read as iChat.

---

# 23. Historical confidence levels

### High confidence

The following are directly supported by historical sources:

* Tiger contained iChat 3.0. ([Macworld][15])
* iChat used Aqua dialogue/speech bubbles and buddy pictures. ([Apple][1])
* Tiger displayed a cloud while a participant was typing. ([Flylib][3])
* Bubble/font colors could be customized. ([ralphjohns.co.uk][4])
* The user's messages were spatially separated from other participants' messages. ([Thought Palace][2])
* The implementation was based around NSTextView/text-system balloons. ([Thought Palace][2])

### Strong inference

It is reasonable to reconstruct the renderer as:

```text
text layout + custom bubble background
```

rather than as a set of bitmap screenshots.

The historical NSTextView statement strongly supports this architecture. ([Thought Palace][2])

### Not established

Apple's exact:

* RGB color constants;
* corner radii;
* gradient stops;
* shadow parameters;
* private bubble classes;
* Tiger source implementation;

were not found in public documentation.

Those should therefore be treated as reconstruction choices rather than historical facts.

---

# 24. Recommended implementation plan

For a GNUstep application intended to feel like **Mac OS X 10.4 iChat**, implement it in this order:

1. **Create the transcript `NSView`.**
2. **Create a `ChatMessage` model.**
3. **Use `NSAttributedString` for message text.**
4. **Measure messages using `NSTextContainer`/`NSLayoutManager`.**
5. **Lay incoming messages against the left margin.**
6. **Lay outgoing messages against the right margin.**
7. **Draw custom `NSBezierPath` bubble shapes.**
8. **Add the tail.**
9. **Add a vertical gradient.**
10. **Add the small Aqua gloss layer.**
11. **Draw the avatar in the opposite margin.**
12. **Add the typing cloud as a transient message object.**
13. **Put the transcript inside an `NSScrollView`.**
14. **Use an ordinary `NSTextView` for composition.**
15. **Add selection/copying after the visual implementation is correct.**

This gets the important historical behavior without depending on Apple's private iChat frameworks.

---

# 25. Bottom line

The most useful lesson from researching iChat is that the famous Aqua bubbles were **a text-layout problem disguised as a piece of visual chrome**.

The essential recipe is:

```text
NSAttributedString
        +
GNUstep text measurement
        +
custom NSBezierPath
        +
Aqua shading/highlight
        +
left/right speaker geometry
        +
avatar
        +
transient typing bubble
```

GNUstep is well suited to this. Its `NSView`, `NSBezierPath`, attributed-string, text-container and layout-manager facilities provide the necessary primitives. ([GNUstep][6])

The one major historical-compatibility trap is assuming that convenient modern Cocoa APIs are necessarily part of the Tiger-era toolkit. For example, GNUstep documents the rounded-rectangle convenience method as Mac OS X 10.5, and `NSGradient` likewise as Mac OS X 10.5. ([GNUstep][7])

For a genuinely Tiger-like implementation, manually construct the Bezier path and, if necessary, manually paint the gradient. That also gives substantially finer control over the final Aqua appearance.

## Sources

* Apple, *Previews iChat Instant Messaging for Mac OS X* — contemporary description of Aqua dialogue bubbles and buddy photos. ([Apple][1])
* Jens Alfke, *The Origin Of The iChat UI* — historical account of the 1997 speech-balloon design and iChat's implementation principles. ([Thought Palace][2])
* Maria Langer, *Mac OS X 10.4 Tiger Visual QuickStart Guide* — contemporary interaction description of the Tiger iChat window and typing clouds. ([Flylib][3])
* Ralph Johns, *iChat Version 2/4 formatting documentation* — historical evidence for bubble/font customization and typing bubbles. ([ralphjohns.co.uk][4])
* GNUstep AppKit documentation — `NSView`, `NSBezierPath`, attributed strings, `NSTextContainer`, `NSLayoutManager`, graphics context and gradients. ([GNUstep][6])
* Apple Human Interface Guidelines — contemporary description of Aqua's antialiasing, transparency, shading and visual principles. ([Scribd][5])

[1]: https://www.apple.com/uk/newsroom/2002/05/06Apple-Previews-iChat-Instant-Messaging-for-Mac-OS-X/?utm_source=chatgpt.com "Apple Previews iChat Instant Messaging for Mac OS X - Apple (UK)"
[2]: https://jens.mooseyard.com/2008/03/18/the-origin-of-the-ichat-ui/?utm_source=chatgpt.com "The Origin Of The iChat UI [Thought Palace]"
[3]: https://flylib.com/books/en/2.585.1.150/1/?utm_source=chatgpt.com "iChat | Mac Os X 10.4 Tiger (Visual Quickstart Guides)"
[4]: https://www.ralphjohns.co.uk/versions/ichat2/howtoFormatText.html?utm_source=chatgpt.com "iChat | Versions | iChat 2 | How to Format a Text Chat"
[5]: https://de.scribd.com/document/992942754/APPLE-Guidelines-2005?utm_source=chatgpt.com "APPLE Guidelines 2005 | PDF | Window (Computing) | Mac Os"
[6]: https://www.gnustep.org/resources/documentation/Developer/Gui/Reference/NSView.html?utm_source=chatgpt.com "NSView"
[7]: https://www.gnustep.org/resources/documentation/Developer/Gui/Reference/NSBezierPath.html?utm_source=chatgpt.com "NSBezierPath.m"
[8]: https://developer.gnustep.org/Manuals/Base/Base-Library.html?utm_source=chatgpt.com "8 Base Library — GNUstep"
[9]: https://www.test.gnustep.org/resources/documentation/Developer/Gui/Reference/NSStringDrawing.html?utm_source=chatgpt.com "NSStringAdditions"
[10]: https://www.gnustep.org/resources/documentation/Developer/Gui/Reference/NSTextContainer.html?utm_source=chatgpt.com "NSTextContainer"
[11]: https://www.gnustep.org/resources/documentation/Developer/Gui/Reference/NSGradient.html?utm_source=chatgpt.com "NSGradient class documentation"
[12]: https://osxdaily.com/2011/12/23/ichat-matte-mod-for-os-x-lion-removes-glossy-text-bubble-ichat/?replytocom=643978&utm_source=chatgpt.com "iChat Matte Mod for OS X Lion Removes Glossy Bubble Text Blocks from iChat"
[13]: https://www.gnustep.org/resources/documentation/Developer/Gui/Reference/NSImage.html?utm_source=chatgpt.com "NSImage"
[14]: https://www.gnustep.org/resources/documentation/Developer/Gui/Reference/NSGraphicsContext.html?utm_source=chatgpt.com "NSGraphicsContext"
[15]: https://www.macworld.com/article/175654/tigerevalichat.html?utm_source=chatgpt.com "Tiger evaluated: iChat | Macworld"
