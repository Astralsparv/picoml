# PicoML Library

## What is PicoML for?

PicoML is a web language, similar to HTML, intended for the Picotron web.
This library is designed in Picotron Lua (a modified form of Lua 5.4)

## Use cases

The PicoML library can be used for implementing support for browsers, e.g: the official [PicoML Browser](https://www.lexaloffle.com/bbs/?tid=152762), creating search engines, e.g: [PicoLoco](https://github.com/Astralsparv/picoloco).
General PicoML can be used to make webpages.

# How to use it

## Creating a page object

Creating a page object is as simple as including the page
```lua
local page=include("picoml.lua")
```

With this, you have an empty page and access to the following functions:
```lua
init()
update()
draw()
setDisplay()
rebuild()

rip()
cleanRip()
extensiveRip()
```
## Building, updating and drawing a page

### > Creating the page object
For this example, we will be using the PicoLoco page, & a 480x270 screen.

Creating a page looks like this:
```lua
local url="https://raw.githubusercontent.com/Astralsparv/picoloco/refs/heads/main/main.picoml" --PicoLoco

local page=include("picoml.lua")

page:init(
    {
        url=url,
        fetch=fetch,
        width=480,
        height=270
    }
)
```

Though, you are highly recommended to push more options, **especially** the permissions property

init() has the properties:

```lua
    url --picoml page
    scripting --boolean, allowing scripts
    permissions --permissions, in the form of a table of permission names
    fetch --a custom fetch function, let's you add custom stuff, e.g: a fetch with caching
    invertScrollX --boolean, whether to invert scrolling on the x axis
    invertScrollY --boolean, whether to invert scrolling on the y axis
    webWarning --a communicating function that lets you handle web warnings (called with webWarning(warning))
    newTab --a communicating function that lets you handle opening new tabs (called with newTab(url,self))
    metadata --a communicating function that lets you receive metadata (called with metadata(meta))
    download --a communicating function that lets you handle downloads (called with download(website,filedata,filename))
    width --number
    height --number
```

An example of this is seen in the PicoML Browser (v7)

```lua
local function newTab(url,self)
    if (self) then
        openTab(url,"self")
    else
        openTab(url)
    end
end
local function metadata(data)
    tabs[index].meta.title=data.title or tabs[index].meta.title
    tabs[index].meta.icon=data.icon or tabs[index].meta.icon
end
local function download(website,source,filename)
    trustedPIDs[create_process("popups/request.lua",
    {
        requestor=cleanLink(website),
        text="Download "..filename,
        parent=pid(),
        accept={
            event="download",
            website=website,
            source=source,
            filename=filename
        }
    })]=true
end
tabs[index].page:init(
{
    url=url,
    scripting=options.pageScripts,
    permissions=defaultPermissions,
    fetch=ffetch,
    invertScrollX=options.invertScrollX,
    invertScrollY=options.invertScrollY,
    webWarning=printh,
    newTab=newTab,
    metadata=metadata,
    download=download,
    width=windowData.width,
    height=windowData.height-17-3-12
}
)
```

The list of permission strings, as of PicoML v2.3 are:
```lua
sprites
map
sound
clipboard
unknownRisky
risky
memory
gui
windows
networking
```

### > Updating the page

Updating the page is as simple as calling `page:update()`
Though, for the cursor to be fed through to the page - you must format the cursor data.
To receive cursor data in Picotron - you can do:
```lua
local curs={}
curs.x, curs.y, curs.b, curs.wheelx, curs.wheely = mouse()
```

It must then be formatted as such to send to the page:
```lua
local cursorData={
    x=curs.x,
    y=curs.y-th,
    b=curs.b,
    wheelx=curs.wheelx,
    wheely=curs.wheely,
}

page:update({mousedata=cursorData})
```

`page:update()` also returns some information, as of v2.2 - it returns:
    cursorSprite - the sprite that the page is wanting to set.

You can set this up with:
```lua
local cursorData={
    x=curs.x,
    y=curs.y-th,
    b=curs.b,
    wheelx=curs.wheelx,
    wheely=curs.wheely,
}

local data=page:update({mousedata=cursorData})
window{cursor=data.cursorSprite}
```
to update a page, sending mouse data & receiving a cursor sprite.


### > Drawing the page

To then draw the page, you can receive a userdata u8 image of the page with `page:draw()`
This can be done with:
```lua
spr(page:draw(),x,y)
```
where x,y is the coordinates of where you want to draw the page in your application.

## Ensuring the page builds correctly

### > Resetting the display

If your application is windowed, or the page itself can be resized - you will need to call `page:setDisplay(width,height)` to re-adjust the page.

This is seen in PicoML v7 with:
```lua

--th variable = the height of the tabs on the PicoML browser, let's the height be adjusted correctly

local screen=get_display() --get the active screen
windowData.width,windowData.height=screen:width(),screen:height() --get the proportions of the page
if (windowData.width!=lastw or windowData.height!=lasth) then --compare the new proportions to the proportions last frame
    --if the proportions have changed, update the display
    page:setDisplay(windowData.width,windowData.height-th) --send the display
end
```

### > Extras

You can rebuild pages with `page:rebuild()`, causing the page to be fully rebuilt (occurs when setDisplay() and init() is called, alongside any update to the page's DOM) for whatever reason you need.

# Ripping pages

## Preparing
Create the page object with
```lua
local page=include("picoml.lua")
```
All forms of ripping has the last return variable of a url - returning a clean form of the url (e.g: example.com to example.com/main.picoml)

## Basic ripping
For a raw pod of the page, you can use basic ripping.
You can get a rip of any page using:
```lua
local data,cleanurl=page:rip(url)
```

## Clean ripping
For a cleaner pod of the page, you can use clean ripping.
As of PicoML 2.2, this makes all urls in "src" and "target" properties absolute - replacing relative paths with their absolute form.
```lua
local data,cleanurl=page:cleanRip(url)
```

## Extensive ripping
Extensive ripping is identical to clean ripping with the bonus of also processing metadata.
You can receive the information with
```lua
local data,meta,cleanurl=page:extensiveRip(url)
```

# Coding a PicoML page

## File types
PicoML pages are stored with the `.picoml` type

## Page structure
PicoML pages are written using a flat DOM, formatted similarly to HTML.

Objects are written as:
```html
<object>text</object>
```
with the opening tag `<object>`, text `text` and closing tag `</object>`
(replacing 'object' with your object type)

You can give objects attributes in the form of:
attr=value
e.g: underlining text
```html
<text underline=true>hello world</text>
```
This can be done infinitely, and must remain in the opening tag only.

You can create a page by pairing these objects together, as seen:

```html
<title>Hello world!</title>
<text>This is my website</text>
<p8text>I created it with PicoML</p8text>
```

## Images

Images can be added into PicoML with the `image` object.

Images are either:
    png
    userdata u8 images
    podded image (what you get when you copy a sprite in the GFX editor)
To set the source of an image, you use the attribute `src`.

For example, setting an image to be a png image:
```html
<image src="image.png"></image>
```
This would create an image, automatically adjusted to the page's proportions, displayed on the webpage.

Setting a podded image would be as such:
```html
<image src='--[[pod_type="gfx"]]unpod("b64:bHo0ALEAAAC4AQAA_gFweHUAQyBAQATw9jPwHDOwBQCvcDM3M-AUMzEzMAkACEuz8BSzBQCPcDNw8wxwM7AHAAGN8ABz_wxz8AQGADAAM-t3AAkFAO9wMzt-IPsMfjszMDM7fgkABo8_dz77BD53PgsAEz9_u34KABBf-gS7-gQIAAjvPxp_Nz67Pjd_PTMwMz0MAA6fcDN9frt_fTOwCAAEYPAAc7s_uwwBDwcAAFQM8wzwFAQAUPMM8P8D")'></image>
```

### > Image Attributes:

`src` - Source of the image (as seen above)

`width` - width (px)

`height` - height (px)

## Metadata

Metadata is used to share information about your page.
As of PML v2.2, officially supported metadata is:
```
title - string, title of the page, displayed in the tab
description - string, description of the page, arbritrary use
author - string, creator/writer of the page, arbritrary use
```

Metadata is added to your page with the `metadata` object.
Each piece of information in the metadata is added with an attribute.

This can be seen through
```html
<metadata title="My PicoML Page" description="The amazing page for the README.md" author="Shopping Cart"></metadata>
```

## Color limitations
Custom color palettes are typically unsupported - but theoretically possible (in conjuction with scripts). Pal 0 and Pal 32 are suggested to remain untouched, used as transparent black & opaque black as issues may occur with images.

## Global attributes

### > General Attributes:

`align` - `left`, `center` or `right` - alignment of the object

`cursor` - `cursorsprite` - the cursor to use when hovering over this object

`class` - the class name of an element, used for styling & scripting

`id` - the id name of an element, used for styling & scripting

### > Event Attributes:

`leftmousedown`

`leftmouseclick`

`leftmouseunpress`


`rightmousedown`

`rightmouseclick`

`rightmouseunpress`


`middlemousedown`

`middlemouseclick`

`middlemouseunpress`


`wheelx`

`wheely`

The following attributes are run:
`update` - alongside _update()
`draw` - alongside _draw()

## Text objects
There are four types of text objects:

`title`, `text`, `p8text` and `link`.

### > Text Attributes:
`color` - color index to set the text color

`hovercolor` - color index to set the text color when you're hovering

`underline` - boolean, whether to underline or not

### > Link Attributes:

`target` - path/link to the file/page

`where` - `self`, `new` - where to open the file

`method` - `download`, `webpage` - whether to download or open it as a page

## Input objects

Input objects are intended for use in conjunction with scripts.
An input object is simply a one-line text input.

### > Attributes:

`placeholder` - the placeholder text to preview until the user has wrote anything

`text` - default input

`color` - color of the text

`background` - color of the background

`placeholder_color` - color of the placeholder text

`width` - width for the textbox

`dynamic_width` - whether the width should dynamically update to fit the user's input

### > Event Attributes:
`enter` - function to be called when the user presses ENTER

`tab` - function to be called when the user presses TAB

## Canvas

The `canvas` element is a canvas used in scripting.
It has a screen being the full width & height of it's element which defaults to a black screen
See the canvas scripting section for how to use it.

## Scripting

Scripts can be added with the `script` object.

Scripts have only one attribute, `src`, which is the filepath/url to a `lua` file.

## Styling

You can add styling with the `style` object.

Styling have only one attribute, `src`, which is the filepath/url to a `style` file.

## Other objects

You can use the `comment` object to write comments in your PicoML code, this is deleted when the page is built automatically.

# Creating style files for PicoML

## File type

PicoML style files use the `.style` extension.

## Structure


Style files are written in the structure of:

```
label
{
properties
}
```

## Labels

The labels allow you to define:

```
system styling (currently just background)
element styling (global element properties)
class styling (any object with this class name)
id styling (the object with this id)
```

### > System

System styling is done by prefixing the label with `__`, these are hard coded to exist.
Leaving the label blank is the same as editing `__page`.
e.g:


```
{
background=7
}
```

or

```
__page
{
background=7
}
```

`__page` (or lack of a label) is the only way to edit the background of the page.

### > Elements

Elements can be styled by simply naming the element in the label.

For example, the element `<text>` can be formatted with:

```
text
{
underline=true
}
```

This affects *all* `text` elements automatically.

### > Classes

Classes can by styled by naming the class, and prefixing it with a `.`

For example, the class named "blue" can be styled with:


```
.blue
{
color=12
}
```

Any element with the class property being "blue" causes it to take the properties of this class, e.g:

```html
<text class="blue">I'm blue!</text>
```

It does not affect anything other than elements with the `blue` class, and can be used on any type of object.

Within elements, you can have multiple classes seperated by spaces, e.g:


```html
<text class="blue p8"></text>
```

```
p8
{
font=2
}
```

This text object would take the properties from both `blue` and `p8`.

### > IDs

IDs can by styled by naming the id, and prefixing it with a `#`

For example, the id named "important" can be styled with:


```
#important
{
color=8
underline=true
}
```

The element with the id `important` causes it to take the properties of the styling defined, e.g:

```html
<text id="important">IMPORTANT: PLEASE READ</text>
```

It does not affect anything other than the element with the id `important`.

## Properties

Properties are defined in the `key=value` structure, identical to how you'd write it for inline properties.

For example, setting the color blue (color index 12) for a text object is done with

```
color=12
```

## Openers/Closers, Curly Braces

The curly braces `{}` are used for opening, `{`, and closing, `}`.

The opening brace, `{`, is used right after the label, marking the start of writing properties.

The closing brace, `}`, is used at the end of writing your properties, causing the styling properties to be saved and implemented

## Priority

Styling priorities (lower number takes priority) are as followed:


```
0 inline text (in the tag)
1 id
2 class
3 element
```

If something has a higher priority and has a property (e.g: color) that a lower priority property also has, the higher priority property takes presedence.

For example:

```html
<text id="grape" class="apple"></text>
```

```
#grape
{
color=18
}

.apple
{
color=8
font=2
}
```

The `apple` class attempts to set the `text` element to be red (8), but as there is inline stlying (highest priority), the color is set to what the id, being purple (18), as it is higher priority.

Because there is no higher priority styling that has a `font` property, the `text` element takes the font from the class `apple`.

# Using lua with PicoML

## File type

PicoML scripts use the `.lua` extension.

## Limitations

Scripts run in a sandboxed setting with access to functions based on what the user permits.

(browsers are able to set permissions for a page, a good browser should allow the user to edit these permissions in some way.)

It is impossible to access the filesystem of a user, with `fetch()` being limited to only being online.

## Manipulating the DOM

### > Fetching elements

You can fetch elements in the page by their id, using:

```lua
local element=dom.getElementById("id")
```

You can get a table of the full DOM of the page using:
```lua
local DOM=dom.get()
```

You can get a table of elements by class name using:
```lua
local elements=dom.getElementsByClassName("class")
```

### > Modifying element properties

With an element, you can use:

```lua
element:set(property,value)
```

to set an element's property, e.g:

```lua
element:set("text","Hello world!")
```

You can move elements within the DOM using

```
dom.moveElementAbove(movingElementID,elementID)
```

```
dom.moveElementBelow(movingElementID,elementID)
```

allowing you to dynamically change the DOM's structure.

### > Reading element properties

With an element, you can simply use

```lua
element.property
```

to read its property.

### > Creating element

You can push an object to the page using

```lua
dom.pushElement(element type,[optional properties])
```

This can be used as seen:

```lua
local text=dom.pushElement("text")
text:set("text","Hello world")
```

The following functions can also be used to create & position the element between other elements.

```lua
dom.pushElementAbove(element type,element to be above,[optional properties])
```

```lua
dom.pushElementBelow(element type,element to be below,[optional properties])
```

## Canvas

The `canvas` object allows you to create a screen that you can draw to cleanly.
You can use a canvas as such:

```lua
local canvas=dom.getElementById("canvas")
canvas:resize(50,50) -- set the proportions to 50x50 (also automatically cls on resize)

function _draw()
    dom.canvas.enter(canvas) -- makes any draw functions apply to the canvas
    cls(14)
    print("Hi!",0,0,7)
    dom.canvas.exit() -- exits the canvas so draw functions apply to the page
end
```

## System Variables

All system variables are suffixed by `__`

These are system variables you have access to:

```
cursorSprite - the sprite of the cursor
mousedata - mouse's data, e.g: positioning and x,y
url - the active page's url
query - the active page's query (?apple=2&grape=4)
queries - the active page's query formatted in a table

scroll - how far the page has scrolled (x=x,y=y)

invertScrollX - whether to invert scrolling on the x axis
invertScrollY - whether to invert scrolling on the y axis
lastCursorData - mousedata of the previous frame
scrollSpeed - speed of scrolling
pageData - page information (width=width, height=height)
viewport - viewport proportions (width=width, height=height)
styling - styling data (system styling, elements, classes & ids)
```

## Built in functions

### > Attaching files

```lua
attach.scripts(filepath) --attach a .lua file
```

```lua
attach.styling(filepath) --attach a .style file
```

### > Opening files

```lua
file.openPage(url,["self","new"]) --open a new page
```

```lua
file.download(filedata/fileurl,filename) --download a file
```

### > Debugging

```lua
webWarning(message) --send a warning
webwarn(message) --send a warning
webWarn(message) --send a warning
warn(message) --send a warning
```

### > DOM

```lua
dom.getElementById(id) --get an element in the DOM by the ID
```

```lua
dom.getElementsByClassName(class) --get multiple elements in the DOM by the class
```

```lua
dom.destroyElement(id) --destroy an element in the DOM
```

```lua
dom.pushElement(tag,[optional extra data]) --create an element at the bottom of the page
dom.pushElementAbove(tag,id,[optional extra data]) --create an element above element with id
dom.pushElementBelow(tag,id,[optional extra data]) --create an element below element with id
```

```lua
dom.moveElementAbove(moving,still,[optional extra data]) --move an element (moving) above an element (still) where each are ids
dom.moveElementBelow(moving,still,[optional extra data]) --move an element (moving) below an element (still) where each are ids
```

```lua
dom.setStyle(label,properties,[replace]) --allows you to change styling during runtime
--label is defined the same as written in .style
--properties is a table of key=value properties
--[replace] is an optional value that deletes all previous styling properties and replaces it with the given properties
```

> Canvas

```lua
dom.canvas.enter(canvasObject) --draw functions go to the canvas screen
```

```lua
dom.canvas.exit() --exit the canvas screen, draw functions go back to the page
```

### > Query

```lua
query.pack(table,string) --does not support nested tables, packs & encodes a query url
```

```lua
query.unpack(query) --unpacks a query
```

### > Local Storage

```lua
localStorage.store(table,filename) --store pods in storage
```

```lua
localStorage.fetch(filename) --fetch pods in storage
```

