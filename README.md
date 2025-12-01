# PicoML Library

## What is it for?

PicoML is a web language, similar to HTML, intended for the Picotron web.
This library is designed in Picotron Lua (a modified form of Lua 5.4)

## Use cases

The PicoML library can be used for implementing support for browsers, e.g: the official [PicoML Browser](https://www.lexaloffle.com/bbs/?tid=152762), creating search engines, e.g: [PicoLoco](https://github.com/Astralsparv/picoloco).

# How to use it

## Creating a page object

Creating a page object is as simple as including the page
```
local page=include("picoml.lua")
```

With this, you have an empty page and access to the following functions:
```
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

### >Creating the page object
For this example, we will be using the PicoLoco page, & a 480x270 screen.

Creating a page looks like this:
```
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

```
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

```
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

The list of permission strings, as of PicoML v2.2 are:
```
logic
variables
graphics
sprites
map
sound
controllerInputs
keyboardInputs
clipboard
unknownRisky
risky
memory
gui
windows
notifications
picotronInformation
dom
fetch
debug
openPages
attachScripts
networking
```

### >Updating the page

Updating the page is as simple as calling ```page:update()```
Though, for the cursor to be fed through to the page - you must format the cursor data.
To receive cursor data in Picotron - you can do:
```
loacl curs={}
curs.x, curs.y, curs.b, curs.wheelx, curs.wheely = mouse()
```

It must then be formatted as such to send to the page:
```
local cursorData={
    x=curs.x,
    y=curs.y-th,
    b=curs.b,
    wheelx=curs.wheelx,
    wheely=curs.wheely,
}

page:update({mousedata=cursorData})
```

```page:update()``` also returns some information, as of v2.2 - it returns:
    cursorSprite - the sprite that the page is wanting to set.

You can set this up with:
```
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


### >Drawing the page

To then draw the page, you can receive a userdata u8 image of the page with ```page:draw()```
This can be done with:
```
spr(page:draw(),x,y)
```
where x,y is the coordinates of where you want to draw the page in your application.

## Ensuring the page builds correctly

### >Resetting the display

If your application is windowed, or the page itself can be resized - you will need to call ```page:setDisplay(width,height)``` to re-adjust the page.

This is seen in PicoML v7 with:
```

--th variable = the height of the tabs on the PicoML browser, let's the height be adjusted correctly

local screen=get_display() --get the active screen
windowData.width,windowData.height=screen:width(),screen:height() --get the proportions of the page
if (windowData.width!=lastw or windowData.height!=lasth) then --compare the new proportions to the proportions last frame
    --if the proportions have changed, update the display
    page:setDisplay(windowData.width,windowData.height-th) --send the display
end
```

## >Extras

You can rebuild pages with ```page:rebuild()```, causing the page to be fully rebuilt (occurs when setDisplay() and init() is called, alongside any update to the page's DOM) for whatever reason you need.

# Ripping pages

## >Preparing
Create the page object with
```
local page=include("picoml.lua")
```
All forms of ripping has the last return variable of a url - returning a clean form of the url (e.g: example.com to example.com/main.picoml)

## >Basic ripping
For a raw pod of the page, you can use basic ripping.
You can get a rip of any page using:
```
local data,cleanurl=page:rip(url)
```

## >Clean ripping
For a cleaner pod of the page, you can use clean ripping.
As of PicoML 2.2, this makes all urls in "src" and "target" properties absolute - replacing relative paths with their absolute form.
```
local data,cleanurl=page:cleanRip(url)
```

## >Extensive ripping
Extensive ripping is identical to clean ripping with the bonus of also processing metadata.
You can receive the information with
```
local data,meta,cleanurl=page:extensiveRip(url)
```