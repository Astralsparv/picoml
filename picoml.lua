--[[pod_format="raw",created="2025-11-28 15:29:10",modified="2025-12-01 13:03:04",revision=1379]]
local ffetch=fetch --replaced in :init() - ensures locality
local webWarning=printh --replaced in :init() - ensures locality
local pageDirty=false
local buildingPage=false

local scripting=false

local baseurl
local page={}
--sandbox functs

local function sandboxedFunct(funct,safe_env,nilerror)
	if (nilerror==nil) nilerror=true
	if safe_env and type(safe_env[funct]) == "function" then
		local ok, err = pcall(safe_env[funct],safe_env)
		if not ok then
			webWarning(funct.."() error: " .. tostring(err))
		end
	elseif (nilerror) then
		webWarning(funct.." not found")
	end
end

--helper
local function swapCase(txt)
	txt=txt:gsub("%a", function(c)
		if c:match("%l") then
			return c:upper()
		else
			return c:lower()
		end
	end)
	return txt
end

--hell
local function textEntities(text)
	text=text:gsub("&lt;","<")
	text=text:gsub("&gt;",">")
	text=text:gsub("&amp;","&")
	text=text:gsub("&quot;",'"')
	text=text:gsub("&apos;","'")
	text=text:gsub("&nbsp;","")
	return text
end

--hell
local function rPath(path, base)
	base=base or baseurl
	local prot = ""
	
	if (path:prot()) return path
	
	local basePath,baseQuery=base:match("^([^?]*)%??(.*)$")
	local pathPart,query=path:match("^([^?]*)%??(.*)$")
	if path:match("^%?") then
		return basePath..path
	end
	
	local pathQuery=(query!="" and query) or nil
	
	if (basePath and basePath!="/") then
		local baseProt = basePath:prot()
		prot=baseProt and (baseProt.."://") or ""
		if (baseProt) then
			basePath=basePath:sub(#prot+1)
		end
		
		local last=basePath:match("[^/]+$")
		if (last) then
			last=last:match("^[^?]+")
			if (last:ext()) then
				basePath=basePath:sub(1,#basePath-#last)
			end
		end
		
		if (basePath:sub(-1)!="/") then
			basePath..="/"
		end
		if (not (path:match("^/"))) then
			pathPart=basePath..pathPart
		end
	end
	
	local segments = {}
	for part in pathPart:gmatch("[^/]+") do
		if (part=="..") then
			if (#segments>0) then
				table.remove(segments)
			end
		elseif (part!="." and part!="") then
			table.insert(segments,part)
		end
	end
	
	pathPart=table.concat(segments, "/")
	
	local lastSegment=pathPart:match("[^/]+$") or ""
	local isFile=(lastSegment:ext()!=nil)
	local finalQuery=pathQuery or (isFile and baseQuery)
	if (finalQuery and finalQuery!="") then
		pathPart..="?"..finalQuery
	end
	return prot..pathPart
end



--resolved fetch, supports ../ and stuff
local function rFetch(path)
	return ffetch(rPath(path,baseurl))
--	if (path:prot()==nil) then
--		local rpath=rPath(path)
--		
--		local base=baseurl
--		return ffetch(base..rpath)
--	else
--		--it's a direct url
--		return ffetch(path)
--	end
end

local function toImage(img,bg)
	if (type(img)=="string") then
		if (img:ext()=="png") then
			img=fetch(img)
			if (type(img)=="userdata") then
				local ud=userdata("u8",img:width(),img:height())
				local trg=get_draw_target()
				set_draw_target(ud)
				cls(32)
				spr(img,0,0)
				set_draw_target(trg)
				return ud
			else
				return nil
			end
		end
		local up=unpod(img)
		if (type(up)=="userdata") return up
		img=rFetch(img)
		if (type(img)=="userdata") then
			return img
		else
			return nil
		end
	end
	if (img==nil) return nil
	return img
end

local function getMetadata(node)
	local meta={}
	--defaults
	meta.title=""
	meta.description=""
	meta.author=""
--	meta.tags={} setup future
	for key,val in pairs(node) do
		local v=val
		if (key=="icon") then
			v=toImage(v)
			if (v) then
				if (v:width()!=10 or v:height()!=10) then
					local temp=userdata("u8",10,10)
					set_draw_target(temp)
					sspr(v,0,0,nil,nil,0,0,10,10)
					set_draw_target()
					v=temp
				end
			end
		end
		if (key!="type") then
			meta[key]=v
		end
	end
	return meta
end

local scripts={}

local function initScripts()
	for i=1, #scripts do
		local ok,err=pcall(scripts[i].fn)
		if (not ok) then
			webWarning("Script runtime error: "..tostr(err))
		else
			sandboxedFunct("_init",scripts[i].env,false)
		end
	end
	scripts={}
end

local function attachScript(src,env,self)
	if (not scripting) return
	if (env.__attachedScripts[src]) return
	env.__attachedScripts[src]=true
	local code=rFetch(src)
	if (code==nil) then
		webWarning("Code not found from "..src)
		return
	end
	local fn,err=load(code, "script", "t", env)
	if (not fn) then
		webWarning("Script compile error: "..tostr(err))
		return
	end
	
	add(scripts,{fn=fn,env=env})
end

local function getElementById(id)
	return page:getElementById(id)
end

local function destroyElement(obj)
	if (type(obj)=="string") then
		obj=page:getRawElementById(obj)
	else
		obj=page:getRawElementById(obj.id)
	end
	del(page.builtPage,obj)
end

local function editableElement(el)
	local wrapper={} --read 
	wrapper._el=el
	
	wrapper.set=function(_,key,val)
		pageDirty=true
		if (key=="text") then
			rawset(el,"rawtext",val)
			rawset(el,"underlinecache",nil)
		elseif (key=="id") then
			if (el.id) then
				page.idLookup[el.id]=nil
			end
			page.idLookup[val]=el
		end
		el[key]=val
	end
	
	setmetatable(wrapper, {
		__index = function(t, k)
			if k == "set" then
				return rawget(t, "set")
			end
			return el[k] -- forward reads to the actual element
		end,
		__newindex = function(t, k, v)
			webWarning("Attempt to modify element directly. Use el:set(key, value)")
		end,
		__metatable = false -- prevent changing metatable
	})
	
	return wrapper
end

local function pushElement(obj,data)
	local obj,success,msg=page:pushElement(obj,data)
	return editableElement(obj),success,msg
end

local function openTab(url,replaceIndex)
	--handle a lack of protocol
	if (sub(url,1,4)!="self" and url:prot()==nil) then
		url="http://"..url
	end
	--handle self: protocol
	local display=url
	if (url:prot()=="self") then
		url=url:sub(8,#url)
		url="self/"..url
	end
	local path,query=url:match("([^?]*)%??(.*)")
	
	--redirect to main.picoml if nil
	local last=path:match("[^/]+$") or ""
	if (last:ext()==nil) then
		if (path:sub(-1)!="/") path..="/"
		path..="main.picoml"
	end
	
	if (query!="") then
		url=path.."?"..query
	else
		url=path
	end
	local selff=false
	if (type(replaceIndex)=="string") then
		if (replaceIndex=="self") selff=true
	end
	page:newTab(url,selff)
end

local function openRelativeTab(url,replaceIndex)
	if (url:prot()==nil) then
		url=rPath(url)
	end
	openTab(url,replaceIndex)
end

--page building

local function wrapText(text,width,charWidth)
	charWidth=charWidth or 5
	local res=""
	local cx=0
	local nl=1
	local fwidth=0
	local i=1
	
	while true do
		local nextnl=text:find("\n",i)
		local segment=nextnl and text:sub(i,nextnl-1) or text:sub(i)
		
		for word in segment:gmatch("%S+") do
			local wordWidth=#word*charWidth
			local spaceWidth=(cx>0) and charWidth or 0
			
			if (wordWidth+spaceWidth>width) then
				res..="\n"
				cx=0
				nl+=1
				spaceWidth=0
			end
			
			if cx>0 then
				res..=" "
				cx+=charWidth
			end
			
			-- split long word if wider than line
			local start=1
			while (start<=#word) do
				local remainingWidth=width-cx
				local fitChars=flr(remainingWidth/charWidth)
				if (fitChars<=0) then
					res..="\n"
					cx=0
					nl+=1
					fitChars=flr(width/charWidth)
				end
				
				local part=word:sub(start,start+fitChars-1)
				res..=part
				cx+=#part*charWidth
				if (cx>fwidth) fwidth=cx
				start+=fitChars
				if (start<=#word) then
					res..="\n"
					cx=0
					nl+=1
				end
			end
		end
		if (not nextnl) break
		res..="\n"
		nl+=1
		cx=0
		i=nextnl+1
	end
	
	return res,nl,fwidth
end


--adds stuff like alignment and margins if missing

local function fixData(data,defaults)
	defaults=defaults or {}
	data.align=data.align or defaults.align or "left"
	data.margin_left=data.margin_left or defaults.margin_left or defaults.margin or data.margin or 0
	data.margin_right=data.margin_right or defaults.margin_right or defaults.margin or data.margin or 0 --not implemented
	data.margin_top=data.margin_top or defaults.margin_top or defaults.margin or data.margin or 0
	data.margin_bottom=data.margin_bottom or defaults.margin_bottom or defaults.margin or data.margin or 0
	return data
end

local function applyMargin(data,x,y)
	return x+data.margin_left,y+data.margin_top
end

local function applyAlignment(align,x,y,width,height,pageData)
	if (align=="center") x=pageData.width/2-width/2
	if (align=="right") x=pageData.width-width
	return x,y
end

local objectHandler={
	text=function(data,builder,pageData,env,x,y)
		data=fixData(data)
		local pushbuild=true
		x,y=builder.x,builder.y
		local rawtext=data.rawtext or data.text or ""
		local text,nl,width=wrapText(rawtext,pageData.width,5)
		local col=data.color or 0
		local height=nl*11
		if (pushbuild) then
			builder.y+=data.margin_top+height+data.margin_bottom
		end
		x,y=applyAlignment(data.align,x,y,width,height,pageData)
		x,y=applyMargin(data,x,y)
		return {
			x=x,y=y,
			width=width,height=height,
			rawtext=rawtext,
			text=text,
			color=col,
			hover=false,
			underline=data.underline,
			draw=function(self)
				print(self.text,self.x,self.y,self.color)
				if (self.underline) then
					if (not self.underlinecache) self.underlinecache=self.text:gsub("[^\n]","_")
					print(self.underlinecache,self.x,self.y+2,self.color)
					print(self.underlinecache,self.x,self.y+2,self.color)
					print(self.underlinecache,self.x-1,self.y+2,self.color)
				end
			end
		},builder
	end,
	title=function(data,builder,pageData,env,x,y)
		data=fixData(data,{margin_top=2,align="center"})
		local pushbuild=true
		x,y=builder.x,builder.y
		local rawtext=data.rawtext or data.text or ""
		local text,nl,width=wrapText(rawtext,pageData.width,10)
		local col=data.color or 0
		local height=nl*22
		if (pushbuild) then
			builder.y+=data.margin_top+height+data.margin_bottom
		end
		x,y=applyAlignment(data.align,x,y,width,height,pageData)
		x,y=applyMargin(data,x,y)
		return {
			x=x,y=y,
			rawtext=data.text,
			text=text,
			color=col,
			width=width,height=height,
			hover=false,
			underline=data.underline,
			draw=function(self)
				print("\^p"..self.text,self.x,self.y,self.color)
				print("\^p"..self.text,self.x,self.y+1,self.color)
				print("\^p"..self.text,self.x+1,self.y,self.color)
				print("\^p"..self.text,self.x+1,self.y+1,self.color)
				if (self.underline) then
					if (not self.underlinecache) self.underlinecache=self.text:gsub("[^\n]","_")
					print("\^p"..self.underlinecache,self.x,self.y+4,self.color)
					print("\^p"..self.underlinecache,self.x-1,self.y+4,self.color)
					print("\^p"..self.underlinecache,self.x-2,self.y+4,self.color)
					print("\^p"..self.underlinecache,self.x-3,self.y+4,self.color)
				end
			end
		},builder
	end,
	link=function(data,builder,pageData,env,x,y)
		data=fixData(data,{})
		local pushbuild=true
		x,y=builder.x,builder.y
		local rawtext=data.rawtext or data.text or ""
		local text,nl,width=wrapText(rawtext,pageData.width,5)
		local col=data.color or 12
		local height=nl*11
		if (pushbuild) then
			builder.y+=data.margin_top+height+data.margin_bottom
		end
		local hovercol=data.hovercolor or 1
		x,y=applyAlignment(data.align,x,y,width,height,pageData)
		x,y=applyMargin(data,x,y)
		local leftmouseclick=[[openTab(self.target,self.where)]]
		if (data.method=="download") then
			leftmouseclick=[[download(self.target)]]
		end
		return {
			x=x,y=y,
			width=width,height=height,
			cursor="pointer",
			rawtext=rawtext,
			text=text,
			color=col,
			hovercol=hovercol,
			target=data.target or "self://404",
			where=data.where or "new",
			hover=false,
			underline=data.underline or true,
			method=data.method or "link",
			draw=function(self)
				local c=self.color
				if (self.hover) then
					c=self.hovercol
				end
				print(self.text,self.x,self.y,c)
				if (self.underline) then
					if (not self.underlinecache) self.underlinecache=self.text:gsub("[^\n]","_")
					print(self.underlinecache,self.x,self.y+2,c)
					print(self.underlinecache,self.x-1,self.y+2,c)
				end
			end,
			leftmouseclick=leftmouseclick,
			middlemouseclick=[[openTab(self.target,"new")]]
		},builder
	end,
	p8text=function(data,builder,pageData,env,x,y)
		data=fixData(data,{margin_bottom=3})
		local pushbuild=true
		x,y=builder.x,builder.y
		local rawtext=data.rawtext or data.text or ""
		local text,nl,width=wrapText(swapCase(rawtext),pageData.width,4)
		local col=data.color or 0
		local height=nl*6
		if (pushbuild) then
			builder.y+=data.margin_top+height+data.margin_bottom
		end
		x,y=applyAlignment(data.align,x,y,width,height,pageData)
		x,y=applyMargin(data,x,y)
		return {
			x=x,y=y,
			rawtext=rawtext,
			text=text,
			color=col,
			width=width,height=height,
			hover=false,
			underline=data.underline,
			draw=function(self)
				print("\014"..self.text,self.x,self.y,self.color)
				if (self.underline) then
					if (not self.underlinecache) self.underlinecache=self.text:gsub("[^ \n]","_")
					print("\014"..self.underlinecache,self.x,self.y+2,self.color)
					print("\014"..self.underlinecache,self.x-1,self.y+2,self.color)
				end
			end
		},builder
	end,
	image=function(data,builder,pageData,env,x,y)
		data=fixData(data)
		
		local pushbuild=true
		x,y=builder.x,builder.y
		local img=toImage(data.src,env.__background)
		if (img) then
			local w=data.width or img:width()
			local h=data.height or img:height()
			
			if (w=="auto") then
				if (h!="auto") then
					w=flr(img:width()*(h/img:height()))
				else
					w=img:width()
				end
				local maxWidth=pageData.width-data.margin_left-data.margin_right
				if (w>maxWidth) then
					local scale = maxWidth / w
					w=flr(w * scale)
				end
			end
			
			if (h=="auto") then
				if (w!="auto") then
					h=flr(img:height()*(w/img:width()))
				else
					h=img:height()
				end
				local maxHeight=pageData.height-data.margin_top-data.margin_bottom
				if (h>maxHeight) then
					local scale=maxHeight/h
					h=flr(h*scale)
				end
			end
			
			local timg = userdata("u8",w,h)
			set_draw_target(timg)
			cls(env.__background)
			sspr(img,0,0,nil,nil,0,0,w,h)
			set_draw_target()
			img=timg
			
			if (pushbuild) then
				builder.y+=data.margin_top+img:height()+data.margin_bottom
			end
			x,y=applyMargin(data,x,y)
			x,y=applyAlignment(data.align,x,y,img:width(),img:height(),pageData)
			
			return {
				x=x,y=y,
				csrc=data.src,
				src=data.src,
				img=img,
				width=img:width(),height=img:height(),
				hover=false,
				draw=function(self)
					spr(self.img,self.x,self.y)
				end
			},builder
		else
			webWarning("Failed to load image from source "..tostr(data.src),1)
			return {
				x=x,y=y,
				width=0,0,
				hover=false
			},builder
		end
	end,
	script=function(data,builder,pageData,env,x,y)
		--delete on init
		return {
			x=0,y=0,
			width=0,height=0,
			src=data.src,
			init=function(self)
				if (self.src) then
					attachScript(self.src,env)
				end
				destroyElement(self)
			end
		},builder
	end,
	comment=function(data,builder,pageData,env,x,y)
		--delete on init, no purpose except commenting code for developers
		return {
			x=0,y=0,
			width=0,height=0,
			init=function(self)
				destroyElement(self)
			end
		},builder
	end,
	input=function(data,builder,pageData,env,x,y)
		--input text
		data=fixData(data)
		local pushbuild=true
		x,y=builder.x,builder.y
		local rawtext=data.rawtext or data.text or ""
		local text=rawtext
		local wwidth=#text*5
		data.dynamic_width=(data.dynamic_width!=nil and data.dynamic_width) or (data.width!=nil)
		local width=data.width or mid(30,wwidth,pageData.width-30)
		local col=data.color or 7
		local bg=data.background or 1
		local height=11
		if (pushbuild) then
			builder.y+=data.margin_top+height+data.margin_bottom
		end
		x,y=applyAlignment(data.align,x,y,width,height,pageData)
		x,y=applyMargin(data,x,y)
		return {
			x=x,y=y,
			width=width,height=height,
			dynamic_width=data.dynamic_width or (data.width!=nil),
			rawtext=rawtext,
			text=text,
			background=bg,
			placeholder=data.placeholder or "",
			placeholder_color=data.placeholder_color or 6,
			color=col,
			hover=false,
			cursor="edit",
			selected=false,
			draw=function(self)
				rectfill(self.x,self.y,self.x+self.width-1,self.y+self.height-1,self.background)
				local t=self.text
				if (#t==0) then
					if (not self.selected) print(self.placeholder,self.x+1,self.y+1,self.placeholder_color)
				else
					print(t,self.x+1,self.y+1,self.color)
				end
				if (self.selected) then
					local xx=self.x+#t*5+1
					local yy=self.y+1
					rectfill(xx,yy,xx+4,yy+8,14)
				end
			end,
			__raw_update=[[
				local inp=readtext()
				if (keyp("enter") and self.enter) self:enter()
				if (keyp("tab") and self.tab) self:tab()
				if (keyp("backspace")) then
					self.text=self.text:sub(1,-2)
				end
				if (inp) then
					self.text..=inp
				end
				if (self.dynamic_width) then
					local t=self.text
					if (#t==0) t=self.placeholder or ""
					self.width=mid(30,#t*5+7,__viewport.width-30)
				end
				--deselect if you click off
				if (not self.hover and __cursorData.b==0x1) self.selected=false
			]],
			leftmouseclick=[[
				self.selected=true
			]]
		},builder
	end
}

--element method
local function callElementMethod(el, method)
	local fn=el[method]
	if (not fn) return
	
	local env=page.env
	
	local ok, err
	--has to be string functions to sandbox
	if (type(fn)=="string") then
		local success, compileErr=load("return function(self) "..fn.." end", "sandboxed", "t", env)
		if (not success) then
			webWarning("Sandbox failed to compile in "..method..": "..tostr(compileErr))
			return
		end
		local func=success()
		ok,err=pcall(func, el)
	elseif (type(fn)=="function") then
		ok, err = pcall(fn, el)
	else
		return
	end
	
	if (not ok) then
		webWarning("Sandbox runtime error in "..method..": "..tostr(err))
	end
end

--rip page

local fails={[[<!DOCTYPE html>
<html>
  <head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Not Found</title>
    <link href="/style.css" rel="stylesheet" type="text/css" media="all">
  </head>
  <body>
    <h1>Page Not Found</h1>
    <p>The requested page was not found.</p>
  </body>
</html>]],[[<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Error</title>
</head>
<body>
]]}

local function ripPage(url,self)
	local raw=ffetch(url)
	if (raw==nil) return nil
	for i=1, #fails do
		if (raw:sub(0,#fails[i])==fails[i]) return nil
	end
	self.rippedPage={}
	for type, attrs, content in raw:gmatch("<([%a_][%w_]*)%s*([^>]*)>(.-)</%1>") do
		local node = {
			type=type,
			text=textEntities(content)
		}
		if (node.text=="") node.text=nil
		
		-- quoted attributes
		for key, quote, val in attrs:gmatch("(%w+)%s*=%s*(['\"])(.-)%2") do
			node[key] = val
		end
		
		-- unquoted attributes excl. spans
		for key, val in attrs:gmatch("([%a_][%w_]*)%s*=%s*([^%s'\"]+)") do
			if (not node[key]) then
				if (val=="true") then
					node[key]=true
				elseif (val=="false") then
					node[key]=false
				elseif (tonum(val)!=nil) then
					node[key]=tonum(val)
				else
					node[key]=val
				end
			end
		end
		add(self.rippedPage,node)
	end
	return self.rippedPage
end


local function drawPage(page,ud)
	local trg=get_draw_target()
	set_draw_target(ud)
	for i=1, #page do
		if (not page[i].ignore) then
			if (page[i].draw) page[i]:draw()
		end
	end
	set_draw_target(trg)
end

local function append(obj,page,builder,pageData,env,self)
	local funct=objectHandler[obj.type]
	if (obj.id) then
		self.idLookup[obj.id]=#page+1
	end
	if (funct) then
		local banned={}
		local scriptingAttribs={
			leftmousedown=true,
			leftmouseclick=true,
			leftmouseunpress=true,
			rightmousedown=true,
			rightmouseclick=true,
			rightmouseunpress=true,
			middlemousedown=true,
			middlemouseclick=true,
			middlemouseunpress=true,
			wheelx=true,
			wheely=true,
			update=true,
			draw=true,
			__raw_update=true,
			enter=true,
			tab=true
		}
		if (not scripting) then
			for k,_ in pairs(scriptingAttribs) do
				banned[k]=true
			end
		end
		local object,newBuilder=funct(obj,builder,pageData,env)
		--set custom values
		for key,val in pairs(obj) do
			if (not banned[key]) then
				object[key]=object[key] or val
			end
		end
		for key,val in pairs(object) do
			if (scriptingAttribs[key]) then
				if (type(val)=="string") then
					local fn,err=load("return function(self) "..val.." end", key, "t", env)
					if (fn) then
						object[key]=fn()
					else
						webWarning("Failed to compile "..key..": "..tostr(err))
						object[key]=nil
					end
				end
			end
		end
		add(page,object)
		builder=newBuilder
		return object,true,"success"
	else
		obj.ignore=true
		add(page,obj)
		return obj,false,"no object handler"
	end
end
-- src being a url, filepath or a table
local function buildPage(src,pageData,env,self)
	buildingPage=true
	local page={idLookup={}}
	self.pageBuilder={
		x=0,y=0
	}
	local meta={}
	if (type(src)=="string") then
		src=ripPage(src,self)
	elseif (type(src)!="table") then
		return false,"can't handle type: "..type(src)
	end
	if (src==nil) printh("src is nil, failed to load page") return false,"src is nil"
	local meta=getMetadata({})
	
	for i=1, #src do
		if (src[i].type=="metadata") then
			meta=getMetadata(src[i])
			append(src[i],page,self.pageBuilder,self.pageData,env,self)
		else
			append(src[i],page,self.pageBuilder,self.pageData,env,self)
		end
		--clear underline cache (for resizing)
		page[#page].underlinecache=nil
	end
	local height=self.pageBuilder.y
	drawPage(page,userdata("u8",1,1)) --flush anything that updates here, e.g: underlinecache
	buildingPage=false
	return src,page,meta,height -- return decompiled form of page, built page, metadata & new height
end

local function updatePage(self,page,cursorData)
	local x,y=cursorData.x,cursorData.y
	--get object at x,y
	local el
	for i=#page,1,-1 do
		if (not page[i].ignore) then
			if (page[i].__raw_update) callElementMethod(page[i],"__raw_update")
			if (page[i].update) callElementMethod(page[i],"update")
			if (page[i]) then
				if (#page>=i) then
					if (page[i].x and page[i].y and page[i].width and page[i].height) then
						if (page[i].x<=x and page[i].x+page[i].width>=x and page[i].y<=y and page[i].y+page[i].height>=y) then
							el=page[i]
						else
							page[i].hover=false
						end
					end
				end
			end
		end
	end
	if (el!=nil) then
		el.hover=true
		if (el.cursor) rawset(self.env,"__cursorSprite",el.cursor)
		--clicking / mousedown
		local mb,lb=cursorData.b,cursorData.lb
		local lclick,rclick,mwclick=lb==0 and mb==1,lb==0 and mb==2,lb==0 and mb==4
		local lunpress=(lb==1 or lb==3 or lb==5 or lb==7) and (lb==0 or lb==2 or lb==6 or lb==4)
		local runpress=(lb==2 or lb==3 or lb==6 or lb==7) and (lb==0 or lb==1 or lb==5 or lb==4)
		local munpress=(lb==4 or lb==5 or lb==6 or lb==7) and (lb==0 or lb==1 or lb==2 or lb==3)
		if (mb==1 or mb==3 or mb==5 or mb==7) then
			if (el.leftmousedown) callElementMethod(el,"leftmousedown")
			if (lclick) then
				if (el.leftmouseclick) callElementMethod(el,"leftmouseclick")
			end
			if (lunpress) then
				if (el.leftmouseunpress) callElementMethod(el,"leftmouseunpress")
			end
		end
		if (mb==2 or mb==3 or mb==6 or mb==7) then
			if (el.rightmousedown) callElementMethod(el,"rightmousedown")
			if (rclick) then
				if (el.rightmouseclick) callElementMethod(el,"rightmouseclick")
			end
			if (runpress) then
				if (el.rightmouseunpress) callElementMethod(el,"leftmouseunpress")
			end
		elseif (mb==4 or mb==6 or mb==7) then
			if (el.middlemousedown) callElementMethod(el,"middlemousedown")
			if (mwclick) then
				if (el.middlemouseclick) callElementMethod(el,"middlemouseclick")
			end
			if (munpress) then
				if (el.middlemouseunpress) callElementMethod(el,"middlemouseunpress")
			end
		end
		--scrollwheel
		local wheelx,wheely=cursorData.wheelx,cursorData.wheely
		if (wheelx!=0 and el.wheelx) callElementMethod(el,"wheelx")
		if (wheely!=0 and el.wheely) callElementMethod(el,"wheely")
	end
end

--sandbox functs
local function sandboxedFetch(path)
	return rFetch(path)
end

local function sandboxedPrinth(text)
	text="WEBPAGE: "..tostr(text)
	printh(text)
end

--data = either website.com/icon.png OR raw filedata
--filename = blank if using website, must set for raw filedata
local function pageDownload(data,filename)
	if (data==nil) webWarning("No data attached to download") return "No data attached to download"
	if (filename==nil) then
		filename=data:basename()
		data=fetch(data)
		if (data==nil) then
			webWarning("Failed to download - download(data/filename,[filename])") return "Failed to download - download(data/filename,[filename])"
		end
	end
	page:download(data,filename)
end

local permittedFunctions={
	logic={
		name="Logic",
		description="Acess to logical functions",
		risk=1,
		functions={
			abs=abs,
			all=all,
			atan2=atan2,
			blit=blit,
			ceil=ceil,
			cos=cos,
			flr=flr,
			mid=mid,
			min=min,
			math=math,
			max=max,
			string=string,
			sub=sub,
			rnd=rnd,
			sgn=sgn,
			sin=sin,
			split=split,
			sqrt=sqrt,
			srand=srand,
			t=t,
			time=time,
		}
	},
	variables={
		name="Variables",
		description="Acess to variable functions",
		risk=1,
		functions={
			USERDATA=USERDATA,
			add=add,
			count=count,
			del=del,
			deli=deli,
			foreach=foreach,
			ipairs=ipairs,
			pairs=pairs,
			get=get,
			chr=chr,
			tonum=tonum,
			tonumber=tonumber,
			tostr=tostr,
			tostring=tostring,
			ord=ord,
			pack=pack,
			set=set,
			unpack=unpack,
			unpod=unpod,
			userdata=userdata,
			utf8=utf8,
			vec=vec,
			table=table,
			type=type,
			pod=pod,
		}
	},
	graphics={
		name="Graphics",
		description="Graphical functions",
		risk=1,
		functions={
			cls=cls,
			color=color,
			clip=clip,
			circ=circ,
			circfill=circfill,
			camera=camera,
			fillp=fillp,
			flip=flip,
			get_display=get_display,
			get_draw_target=get_draw_target,
			set_draw_target=set_draw_target,
			line=line,
			oval=oval,
			ovalfill=ovalfill,
			rect=rect,
			rectfill=rectfill,
			tline=tline,
			tline3d=tline3d,
			pset=pset,
			pget=pget,
			print=print,
			pal=pal,
			palt=palt,
			select=select
		}
	},
	sprites={
		name="Sprites",
		description="Read/write to the sprites",
		risk=1,
		functions={
			set_spr=set_spr,
			get_spr=get_spr,
			fget=fget,
			fset=fset,
			spr=spr,
			sspr=sspr,
		}
	},
	map={
		name="Map",
		description="Read/write to the map",
		risk=1,
		functions={
			map=map,
			mget=mget,
			mset=mset,
		}
	},
	sound={
		name="Sound",
		description="Play sounds",
		risk=1,
		functions={
			music=music,
			note=note,
			sfx=sfx
		}
	},
	controllerInputs={
		name="Controller",
		description="Read controller inputs",
		risk=1,
		functions={
			btn=btn,
			btnp=btnp
		}
	},
	keyboardInputs={
		name="Keyboard",
		description="Access keyboard inputs",
		risk=2,
		functions={
			key=key,
			keyp=keyp,
			peektext=peektext,
			readtext=readtext,
		}
	},
	clipboard={
		name="Clipboard",
		description="Read/write to the clipboard",
		risk=2,
		functions={
			get_clipboard=get_clipboard,
			set_clipboard=set_clipboard,
		}
	},
	unknownRisky={ --unknown security risks or what functions do
		name="Unknown",
		description="Unknown functions, can open security risks",
		risk=5,
		functions={
			create_meta_key=create_meta_key,
			getmetatable=getmetatable,
			setmetatable=setmetatable,
			rawequal=rawequal,
			rawget=rawget,
			rawlen=rawlen,
			rawset=rawset,
			tokenoid=tokenoid
		}
	},
	risky={ --100% risky.
		name="Miscellaneous risky",
		description="Random miscellaneous risky functions",
		risk=3,
		functions={
			load=load,
			mouselock=mouselock
		}
	},
	memory={ --100% risky.
		name="Memory",
		description="Ability to edit the memory of the process",
		risk=5,
		functions={
			unmap=unmap,
			map=map,
			poke=poke,
			peek=peek
		}
	},
	gui={
		name="GUIs",
		description="Ability to create GUIs",
		risk=1,
		functions={
			create_gui=create_gui
		}
	},
	windows={ --access the browser window info & sending stuff, sketch.
		name="Windows",
		description="Ability to access the picotron environment",
		risk=5,
		functions={
			on_event=on_event,
			env=env,
			pid=pid,
			send_message=send_message
		}
	},
	notifications={
		name="Notifications",
		description="Ability to create notifications",
		risk=1,
		functions={
			notify=notify
		}
	},
	picotronInformation={
		name="Picotron Information",
		description="Ability to access information like date & stat",
		risk=1,
		functions={
			date=date,
			stat=stat
		}
	},
	dom={
		name="DOM",
		description="Ability to access the DOM",
		risk=1,
		functions={
			getElementById=getElementById,
			destroyElement=destroyElement,
			pushElement=pushElement
		}
	},
	fetch={
		name="Fetch",
		description="Ability to fetch files (online only)",
		risk=2,
		functions={
			fetch=sandboxedFetch
		}
	},
	debug={
		name="Debug",
		description="Debug tools",
		risk=1,
		functions={
			warn=webWarning,
			webwarn=webWarning,
			webWarn=webWarning,
			webWarning=webWarning,
			printh=sandboxedPrinth
		}
	},
	openPages={
		name="Open Pages",
		description="Ability to open/close pages",
		risk=2,
		functions={
			openTab=openRelativeTab,
			openRelativeTab=openRelativeTab,
			download=pageDownload
		}
	},
	attachScripts={
		name="Attach Scripts",
		description="Ability to attach scripts (sandboxed)",
		risk=1,
		functions={
			attachScripts=attachScripts
		}
	},
	networking={
		socket=socket
	}
}

local function loadPermissions(environment,allowed)
	for i=1, #allowed do
		if (permittedFunctions[allowed[i]]) then
			for key,val in pairs(permittedFunctions[allowed[i]].functions) do
				environment[key]=val
			end
		end
	end
	return environment
end

--sandbox

local function buildEnvironment(permissions,data,pageData)
	local scriptEnvironment={}
	scriptEnvironment.__scroll={x=0,y=0}
	scriptEnvironment.__cursorData={x=0,y=0,rawx=0,rawy=0,b=0,wheelx=0,wheely=0,lb=0}
	scriptEnvironment.__lastCursorData={x=0,y=0,rawx=0,rawy=0,b=0,wheelx=0,wheely=0,lb=0}
	scriptEnvironment.__background=data.background or 7
	scriptEnvironment.__invertScrollX=data.invertScrollX or false
	scriptEnvironment.__invertScrollY=data.invertScrollY or false
	scriptEnvironment.__scrollSpeed=data.scrollSpeed or 8
	scriptEnvironment.__pageData=pageData
	scriptEnvironment.__viewport={width=0,height=0}
	scriptEnvironment.__attachedScripts={} --unlisted
	--allowed defaults
	scriptEnvironment=loadPermissions(scriptEnvironment,permissions)
--	setmetatable(scriptEnvironment, {
--		__newindex = function(_, key, value)
--			if type(value) == "function" then
--				rawset(scriptEnvironment, key, value) -- allow defining global functions
--			else
--				error("You cannot define new global variables: "..key)
--			end
--		end
--	})
	local code=[[
		function __raw_update()
			if (__invertScrollX) then
				__scroll.x+=__cursorData.wheelx*__scrollSpeed
			else
				__scroll.x-=__cursorData.wheelx*__scrollSpeed
			end
			if (__invertScrollY) then
				__scroll.y+=__cursorData.wheely*__scrollSpeed
			else
				__scroll.y-=__cursorData.wheely*__scrollSpeed
			end
			__scroll.x=mid(0,__scroll.x,max(0,__pageData.width-__viewport.width))
			__scroll.y=mid(0,__scroll.y,max(0,__pageData.height-__viewport.height))
			__scrollbarVisible=__pageData.height>__viewport.height
		end
	]]
	local fn,err=load(code, "script", "t", scriptEnvironment)
	if (not fn) then
		webWarning("RAW Script compile error: "..tostr(err))
	else
		local ok,err2=pcall(fn)
		if (not ok) then
			webWarning("Script runtime error: "..tostr(err2))
		else
			
		end
	end
	return scriptEnvironment
end

--code here

--communicate with thyself
page.getElementById = function(self, id)
	local el = self.builtPage[self.idLookup[id]]
	if (not el) return nil
	
	return editableElement(el)
end

page.getRawElementById = function(self, id)
	local el = self.builtPage[self.idLookup[id]]
	if (not el) return nil
	
	return el
end

page.pushElement=function(self,obj,data)
	if (type(obj)=="string") then
		obj={type=obj}
	end
	if (data) then
		for k,v in pairs(data) do
			obj[k]=v
		end
	end
	local obj,success,msg=append(obj,self.builtPage,self.pageBuilder,self.pageData,self.env,self)
	return obj,success,msg
end

page.newTab=function(self,url,selff)
	self.browserCommunication.newTab(url,selff)
end

page.download=function(self,data,filename)
	self.browserCommunication.download(baseurl,data,filename)
end

--[[
:init(data) returns nil
:update(mousedata) returns the cursor sprite
:draw() returns the u8 of the page

:env() --returns the environment of the page's scripts
:setDisplay(width,height) --update the page's viewport

pageData=page information - width, height, background
rippedPage=ripped page contents as a table
builtPage=page with the contents built (so that they have their functions and properties)
]]--

page.setDisplay=function(self,width,height,generate)
	if (generate==nil) generate=true
	local lw,lh=self.width,self.height
	self.width=width
	self.height=height
	self.pageData.width=width
	if (generate and (self.width!=lw and self.height!=lh)) then
		pageDirty=true
	end
end

page.rip=function(self,url)
	if (url:ext()==nil) url=url.."/"
	if (url:sub(-1)=="/") then
		url=url.."main.picoml"
	end
	local rip=ripPage(url,self)
	local meta={}
	baseurl=url
	return rip,url
end

page.cleanRip=function(self,url)
	local rip,url=page:rip(url)
	if (rip==nil) return nil
	local start=url
	if (start:ext()!=nil) then
		start=start:sub(1,#start-#start:basename())
	end
	--clean form which localises src and target
	for i=1, #rip do
		if (rip[i].src) rip[i].src=rPath(rip[i].src,start)
		if (rip[i].target) rip[i].target=rPath(rip[i].target,start)
	end
	return rip,url
end

--cleanRip + metadata
page.extensiveRip=function(self,url)
	local rip,url=page:rip(url)
	if (rip==nil) return nil
	local start=url
	if (start:ext()!=nil) then
		start=start:sub(1,#start-#start:basename())
	end
	--clean form which localises src and target
	for i=1, #rip do
		if (rip[i].src) rip[i].src=rPath(rip[i].src,start)
		if (rip[i].target) rip[i].target=rPath(rip[i].target,start)
		--also get meta
		if (rip[i].type=="metadata") then
			meta=getMetadata(rip[i])
		end
	end
	return rip,meta,url
end

page.rebuild=function(self)
	if (not self.hasinit) return
	self.idLookup={}
	if (not self.builtPage) then
		self.builtPage=self.rippedPage
	end
	_,self.builtPage,self.meta,self.pageData.height=buildPage(self.builtPage,self.pageData,self.env,self)
	self.browserCommunication.metadata(self.meta or {})
	for i=1, #self.builtPage do
		if (self.builtPage[i].init) self.builtPage[i]:init()
	end
end

local function packQuery(query)
	local result={}
	for key,val in string.gmatch(query,"([^&=]+)=([^&=]+)") do
		local num=tonumber(val)
		if (num) then
			result[key]=num
		else
			value=value:gsub('^"(.*)"$',"%1")
			result[key]=val
		end
	end
	return result
end

page.init=function(self,data)
	baseurl=data.url
	scripting=data.scripting
	local _
	webWarning=data.webWarning or printh
	self.env=buildEnvironment(data.permissions,data,self.pageData)
	rawset(self.env,"__url",baseurl)
	local _,query=baseurl:match("^([^?]*)%??(.*)$")
	rawset(self.env,"__query",query)
	rawset(self.env,"__queries",packQuery(query))
	self.pageData={width=0,height=0}
	self:setDisplay(data.width,data.height,false)
	ffetch=data.fetch
	self.rippedPage=ripPage(data.url,self)
	if (self.rippedPage==nil) return "404"
	self.lastcurs={}
	self.browserCommunication={}
	self.browserCommunication.newTab=data.newTab
	self.browserCommunication.metadata=data.metadata
	self.browserCommunication.download=data.download
	self.hasinit=true
	self:rebuild()
	initScripts()
end

page.update=function(self,data)
	if (self.rippedPage==nil) return "404"
	if (not self.hasinit) return {}
	initScripts()
	if (pageDirty) pageDirty=false self:rebuild()
	local curs=data.mousedata
	--ensure only affects if in page viewport
	if (curs.x<0 or curs.y<0 or curs.x>self.width or curs.y>self.height) then
		curs=self.env.__lastCursorData
	else
		curs.y+=self.env.__scroll.y
	end
	curs.lb=self.env.__lastCursorData.b
	self.env.__lastCursorData=curs
	rawset(self.env,"__cursorData",curs)
	rawset(self.env,"__pageData",self.pageData)
	rawset(self.env,"__viewport",{width=self.width,height=self.height})
	rawset(self.env,"__cursorSprite",1)
	updatePage(self,self.builtPage,curs)
	sandboxedFunct("__raw_update",self.env,false)
	sandboxedFunct("_update",self.env,false)
	return {
		cursorSprite=self.env.__cursorSprite
	}
end

page.draw=function(self,x,y)
	if (self.hasinit==false or self.rippedPage==nil) return userdata("u8",1,1)
	local scroll=self.env.__scroll
	camera(scroll.x,scroll.y)
	local w,h=self.width,self.height
	local ud=userdata("u8",w,h)
	set_draw_target(ud)
	pal(0,32)
	cls(self.env.__background)
	drawPage(self.builtPage,ud)
	camera()
	sandboxedFunct("_draw",self.env,false)
	if (self.env.__scrollbarVisible) then
		rectfill(w-5,th,w,h,13)
		local y=min(h-5,((scroll.y)/(self.pageData.height-h))*(h-5))
		rectfill(w-5,y,w,y+5,29)
	end
	set_draw_target()
	pal(0,0)
	palt(0,true)
	return ud
end

page.hasinit=false
return page,"2.2.1"