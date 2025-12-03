local ffetch=fetch --replaced in :init() - ensures locality
local webWarning=printh --replaced in :init() - ensures locality
local pageDirty=false
local buildingPage=false

local scripting=false

local fonts={
	{width=5,height=10}, --pt
	{width=4,height=6}   --p8
}

local rootFolder="/appdata/picoml/"
local localStorageFolder=rootFolder.."localStorage/"
local sharedStorageFolder=rootFolder.."sharedStorage/"
mkdir(rootFolder)
mkdir(localStorageFolder)
mkdir(sharedStorageFolder)
local baseurl
local page={}

local function cleanURL(url)
	local url,_=url:match("([^?]*)%??(.*)")
	url=url:sub(#url:prot()+4,#url)
	local rem="/main.picoml"
	if (url:sub(#url-#rem+1,#url)==rem) then
		url=url:sub(1,#url-#rem)
	end
	local sectors=url:split("/")
	return sectors[1] or url
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
end

--styling
local function attachStyling(style,env)
	if (env.__attachedStyling[style]) return
	env.__attachedStyling[style]=true
	if (type(style)=="string") then
		if (style:ext()=="style") then
			local data=rFetch(style)
			if (data) then
				data=data:split("\n")
				local obj=""
				local typ=""
				local properties={}
				for i=1, #data do
					local s=data[i]
					--why is there a \n remnant?
					--last index doesn't have remnant
					if (i<#data) then
						s=s:sub(1,-2)
					end
					if (s!="") then
						local info=s:split("=")
						if (#info==1) then
							--name, opener, closer
							if (s=="{") then
								if (obj=="") then --blank == defaults
									obj="page" --(alias)
									typ="system"
								end
							elseif (s=="}") then
								--closer, push to styling
								if (env.__styling[typ][obj]==nil) env.__styling[typ][obj]={}
								for k,v in pairs(properties) do
									env.__styling[typ][obj][k]=v
								end
								properties={}
								obj=""
							elseif (#s>0) then --ensure not a blank line
								local ss=s
								typ="element"
								if (s:sub(1,1)==".") then
									typ="class"
									ss=ss:sub(2)
								elseif (s:sub(1,1)=="#") then
									typ="id"
									ss=ss:sub(2)
								elseif (s:sub(1,2)=="__") then
									typ="system"
									ss=ss:sub(2)
								end
								obj=ss --set name
							end
						elseif (#info==2) then
							--k,v
							local k,v=info[1],info[2]
							properties[k]=v
						end
					end
				end
			end
			pageDirty=true
		else
			webWarning("Invalid Styling format. (.style file)")
		end
	else
		webWarning("Invalid Styling format. (.style file)")
	end
end

local cacheCanvas=""
--canvas
local function enterCanvas(canvas)
	if (canvas.screen) then
		if (cacheCanvas=="") cacheCanvas=get_draw_target()
		set_draw_target(canvas.screen)
	end
end

local function exitCanvas()
	if (cacheCanvas!="") then
		set_draw_target(cacheCanvas)
		cacheCanvas=""
	end
end

--query strings
local function packQuery(str) --does not support nested tables
	if (type(str)=="table") then
		local res=""
		for k,v in pairs(str) do
			res..=packQuery(k).."="..packQuery(v).."&"
		end
		if (res:sub(-1)=="&") res=res:sub(1,#res-1)
		return res
	elseif (type(str)!="string") then
		str=tostr(str) --is this the right thing to do?
	end
	return (str:gsub("([^A-Za-z0-9%-_%.~])", function(c)
		return string.format("%%%02X", string.byte(c))
	end))
end

local function unpackQuery(str)
	local res={}
	
	for pair in string.gmatch(str,"([^&]+)") do
		local key,val=pair:match("([^=]+)=?(.*)")
		if (key and val) then
			key=key:gsub("+"," "):gsub("%%(%x%x)", function(h)
				return string.char(tonumber(h,16))
			end)
			val=val:gsub("+"," "):gsub("%%(%x%x)", function(h)
				return string.char(tonumber(h,16))
			end)
			local num=tonumber(val)
			if num then
				res[key]=num
			else
				res[key]=val
			end
		end
	end
	
	return res
end

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

local function toImage(img,bg)
	if (type(img)=="string") then
		if (img:ext()=="png") then
			img=rFetch(img)
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

local function getElementsByClassName(class)
	return page:getElementsByClassName(class)
end

local function getDOM()
	return page:getDOM()
end

local function moveElementAbove(moving,still)
	if (type(moving)=="string") then
		moving=page:getElementIndexById(moving)
	else
		moving=page:getElementIndexById(moving.id)
	end
	
	if (type(still)=="string") then
		still=page:getElementIndexById(still)
	else
		still=page:getElementIndexById(still.id)
	end
	return page:moveElementAbove(moving,still)
end

local function moveElementBelow(moving,still)
	if (type(moving)=="string") then
		moving=page:getElementIndexById(moving)
	else
		moving=page:getElementIndexById(moving.id)
	end
	
	if (type(still)=="string") then
		still=page:getElementIndexById(still)
	else
		still=page:getElementIndexById(still.id)
	end
	return page:moveElementBelow(moving,still)
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
	
	wrapper.resize=function(_,width,height)
		el.width,el.height=width,height
		page:rebuild()
	end
	
	setmetatable(wrapper, {
		__index = function(t, k)
			if k == "set" then
				return rawget(t, "set")
			end
			if k == "resize" then
				return rawget(t, "resize")
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

local function pushElementAbove(obj,obj2,data)
	local obj,success,msg=page:pushElementAbove(obj,obj2,data)
	return editableElement(obj),success,msg
end

local function pushElementBelow(obj,obj2,data)
	local obj,success,msg=page:pushElementBelow(obj,obj2,data)
	return editableElement(obj),success,msg
end

local function setStyle(label,properties,replace)
    page:setStyle(label,properties,replace)
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
	
	if (text==nil) return "",0,0
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

local function fixData(data,class,id,env)
	if (data.inline==nil) data.inline=unpod(pod(data)) --clone
	local inline=data.inline
	local element=data.type
	class=class or ""
	defaults=defaults or {}
	local push={}
	--priority:
	-- 1 data given in tag
	-- 2 id
	-- 3 class
	-- 4 element
	-- 5 pure defaults
	-- 6 default element
	
	push={ --pure defaults
		align="left",
		margin_left=0,
		margin_right=0,
		margin_top=0,
		margin_bottom=0
	}
	if (env.__styling.defaultElement[element]) then
		for k,v in pairs(env.__styling.defaultElement[element]) do
			push[k]=v
		end
	end
	if (env.__styling.element[element]) then
		for k,v in pairs(env.__styling.element[element]) do
			push[k]=v
		end
	end
    --split into different classes
    local classes=class:split(" ")
    for i=1, #classes do
    	if (classes[i]!="") then
	    	if (env.__styling.class[classes[i]]) then
	    		for k,v in pairs(env.__styling.class[classes[i]]) do
	    			push[k]=v
	    		end
	    	end
	    end
	end
    
	if (env.__styling.id[id]) then
		for k,v in pairs(env.__styling.id[id]) do
			push[k]=v
		end
	end
	
	for k,v in pairs(inline) do
		push[k]=v
	end
	
	for k,v in pairs(push) do
		data[k]=v
	end
	
	if (data.font) then
		if (data.font!=1 and data.font!=2) data.font=1
	end
	
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
		data=fixData(data,data.class,data.id,env)
		local pushbuild=true
		x,y=builder.x,builder.y
		local rawtext=data.rawtext or data.text
		local font=data.font
		local text,nl,width=wrapText(rawtext,pageData.width,fonts[font].width)
		if (font==2) text=swapCase(text)
		local height=nl*fonts[font].height
		if (pushbuild) then
			builder.y+=data.margin_top+height+data.margin_bottom
		end
		x,y=applyAlignment(data.align,x,y,width,height,pageData)
		x,y=applyMargin(data,x,y)
		
		local el={
			x=x,y=y,
			width=width,height=height,
			rawtext=rawtext,
			text=text,
			hover=false,
			draw=function(self)
				local prefix=""
				if (self.font==2) prefix="\014"
				local c=self.color
				if (self.hover and self.hovercolor) then
					c=self.hovercolor
				end
				print(prefix..self.text,self.x,self.y,c)
				if (self.underline) then
					if (not self.underlinecache) self.underlinecache=self.text:gsub("[^\n]","_")
					print(prefix..self.underlinecache,self.x,self.y+2,c)
					print(prefix..self.underlinecache,self.x,self.y+2,c)
					print(prefix..self.underlinecache,self.x-1,self.y+2,c)
				end
			end
		}
		for k,v in pairs(data) do
			if (el[k]==nil) then
				el[k]=v
			end
		end
		return el,builder
	end,
	title=function(data,builder,pageData,env,x,y)
		data=fixData(data,data.class,data.id,env)
		local pushbuild=true
		x,y=builder.x,builder.y
		local rawtext=data.rawtext or data.text or ""
		local font=data.font
		--*2 because title
		local text,nl,width=wrapText(rawtext,pageData.width,fonts[font].width*2)
		if (font==2) text=swapCase(text)
		local height=nl*fonts[font].height*2
		if (pushbuild) then
			builder.y+=data.margin_top+height+data.margin_bottom
		end
		x,y=applyAlignment(data.align,x,y,width,height,pageData)
		x,y=applyMargin(data,x,y)
		local el={
			x=x,y=y,
			rawtext=data.text,
			text=text,
			width=width,height=height,
			hover=false,
			draw=function(self)
				local prefix="\^p"
				if (font==2) prefix..="\014"
				local c=self.color
				if (self.hover and self.hovercolor) then
					c=self.hovercolor
				end
				print(prefix..self.text,self.x,self.y,c)
				print(prefix..self.text,self.x,self.y+1,c)
				print(prefix..self.text,self.x+1,self.y,c)
				print(prefix..self.text,self.x+1,self.y+1,c)
				if (self.underline) then
					if (not self.underlinecache) self.underlinecache=self.text:gsub("[^\n]","_")
					print(prefix..self.underlinecache,self.x,self.y+4,c)
					print(prefix..self.underlinecache,self.x-1,self.y+4,c)
					print(prefix..self.underlinecache,self.x-2,self.y+4,c)
					print(prefix..self.underlinecache,self.x-3,self.y+4,c)
				end
			end
		}
		for k,v in pairs(data) do
			if (el[k]==nil) then
				el[k]=v
			end
		end
		
		return el,builder
	end,
	link=function(data,builder,pageData,env,x,y)
		data=fixData(data,data.class,data.id,env)
		local pushbuild=true
		x,y=builder.x,builder.y
		local rawtext=data.rawtext or data.text or ""
		local font=data.font
		local text,nl,width=wrapText(rawtext,pageData.width,fonts[font].width)
		local height=nl*fonts[font].height
		if (pushbuild) then
			builder.y+=data.margin_top+height+data.margin_bottom
		end
		x,y=applyAlignment(data.align,x,y,width,height,pageData)
		x,y=applyMargin(data,x,y)
		local leftmouseclick=[[file.openPage(self.target,self.where)]]
		if (data.method=="download") then
			leftmouseclick=[[file.download(self.target)]]
		end
		local el={
			x=x,y=y,
			width=width,height=height,
			rawtext=rawtext,
			text=text,
			hover=false,
			draw=function(self)
				local c=self.color
				if (self.hover and self.hovercolor) then
					c=self.hovercolor
				end
				print(self.text,self.x,self.y,c)
				if (self.underline) then
					if (not self.underlinecache) self.underlinecache=self.text:gsub("[^\n]","_")
					print(self.underlinecache,self.x,self.y+2,c)
					print(self.underlinecache,self.x-1,self.y+2,c)
				end
			end,
			leftmouseclick=leftmouseclick,
			middlemouseclick=[[file.openPage(self.target,"new")]]
		}
		for k,v in pairs(data) do
			if (el[k]==nil) then
				el[k]=v
			end
		end
		
		return el,builder
	end,
	image=function(data,builder,pageData,env,x,y)
		data=fixData(data,data.class,data.id,env)
		
		local pushbuild=true
		x,y=builder.x,builder.y
		local img=toImage(data.src,env.__styling.system.page.background)
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
			cls(env.__styling.system.page.background)
			sspr(img,0,0,nil,nil,0,0,w,h)
			set_draw_target()
			img=timg
			
			if (pushbuild) then
				builder.y+=data.margin_top+img:height()+data.margin_bottom
			end
			x,y=applyMargin(data,x,y)
			x,y=applyAlignment(data.align,x,y,img:width(),img:height(),pageData)
			
			local el={
				x=x,y=y,
				csrc=data.src,
				src=data.src,
				img=img,
				width=img:width(),height=img:height(),
				hover=false,
				draw=function(self)
					spr(self.img,self.x,self.y)
				end
			}
			for k,v in pairs(data) do
				if (el[k]==nil) then
					el[k]=v
				end
			end
			return el,builder
		else
			webWarning("Failed to load image from source "..tostr(data.src),1)
			local el={
				x=x,y=y,
				width=0,0,
				hover=false
			}
			for k,v in pairs(data) do
				if (el[k]==nil) then
					el[k]=v
				end
			end
			
			return el,builder
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
	style=function(data,builder,pageData,env,x,y)
		--delete on init
		return {
			x=0,y=0,
			width=0,height=0,
			src=data.src,
			init=function(self)
				if (self.src) then
					attachStyling(self.src,env)
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
		data=fixData(data,data.class,data.id,env)
		local pushbuild=true
		x,y=builder.x,builder.y
		local rawtext=data.rawtext or data.text or ""
		local text=rawtext
		local wwidth=#text*5
		local height=data.height
		local width=data.width or mid(30,wwidth,pageData.width-30)
		if (pushbuild) then
			builder.y+=data.margin_top+height+data.margin_bottom
		end
		x,y=applyAlignment(data.align,x,y,width,height,pageData)
		x,y=applyMargin(data,x,y)
		local el={
			x=x,y=y,
			width=width,
			rawtext=rawtext,
			text=text,
			hover=false,
			selected=false,
			draw=function(self)
				local c=self.color
				if (self.hover and self.hovercolor) then
					c=self.hovercolor
				end
				rectfill(self.x,self.y,self.x+self.width-1,self.y+self.height-1,self.background)
				local t=self.text
				if (#t==0) then
					if (not self.selected) print(self.placeholder,self.x+1,self.y+1,self.placeholder_color)
				else
					print(t,self.x+1,self.y+1,c)
				end
				if (self.selected) then
					local xx=self.x+#t*5+1
					local yy=self.y+1
					rectfill(xx,yy,xx+4,yy+8,14)
				end
			end,
			__raw_update=[[
				if (self.selected) then
					local inp=readtext()
					if (keyp("enter") and self.enter) self:enter()
					if (keyp("tab") and self.tab) self:tab()
					if (keyp("backspace")) then
						self.text=self.text:sub(1,-2)
					end
					if (inp) then
						self.text..=inp
					end
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
		}
		for k,v in pairs(data) do
			if (el[k]==nil) then
				el[k]=v
			end
		end
		
		return el,builder
	end,
	gap=function(data,builder,pageData,env,x,y)
		--input text
		data=fixData(data,data.class,data.id,env)
		local pushbuild=true
		x,y=builder.x,builder.y
		local height=data.height
		if (pushbuild) then
			builder.y+=data.margin_top+height+data.margin_bottom
		end
--		x,y=applyAlignment(data.align,x,y,width,height,pageData) why
		x,y=applyMargin(data,x,y) --also why but more seen why
		local el={
			x=x,y=y,
			width=0
		}
		for k,v in pairs(data) do
			if (el[k]==nil) then
				el[k]=v
			end
		end
		return el,builder
	end,
	canvas=function(data,builder,pageData,env,x,y)
		data=fixData(data,data.class,data.id,env)
		local pushbuild=true
		x,y=builder.x,builder.y
		local width=data.width or 50
		local height=data.height or 50
		if (pushbuild) then
			builder.y+=data.margin_top+height+data.margin_bottom
		end
		x,y=applyAlignment(data.align,x,y,width,height,pageData)
		x,y=applyMargin(data,x,y)
		local el={
			x=x,y=y,
			width=width,height=height,
			hover=false,
			__raw_update=function(self)
				if (self.screen==nil or self.width!=self.screen:width() or self.height!=self.screen:height()) then
					self.screen=userdata("u8",self.width,self.height)
				end
			end,
			draw=function(self)
				spr(self.screen,self.x,self.y)
			end
		}
		for k,v in pairs(data) do
			if (el[k]==nil) then
				el[k]=v
			end
		end
		
		return el,builder
	end,
	
	--deprecated elements, keeping for compatibility
	p8text=function(data,builder,pageData,env,x,y) --deprec. 2.3
		data=fixData(data,data.class,data.id,env)
		local pushbuild=true
		x,y=builder.x,builder.y
		local rawtext=data.rawtext or data.text or ""
		local text,nl,width=wrapText(swapCase(rawtext),pageData.width,4)
		local height=nl*6
		if (pushbuild) then
			builder.y+=data.margin_top+height+data.margin_bottom
		end
		x,y=applyAlignment(data.align,x,y,width,height,pageData)
		x,y=applyMargin(data,x,y)
		local el={
			x=x,y=y,
			rawtext=rawtext,
			text=text,
			width=width,height=height,
			hover=false,
			draw=function(self)
				local c=self.color
				if (self.hover and self.hovercolor) then
					c=self.hovercolor
				end
				print("\014"..self.text,self.x,self.y,c)
				if (self.underline) then
					if (not self.underlinecache) self.underlinecache=self.text:gsub("[^ \n]","_")
					print("\014"..self.underlinecache,self.x,self.y+2,c)
					print("\014"..self.underlinecache,self.x-1,self.y+2,c)
				end
			end
		}
		for k,v in pairs(data) do
			if (el[k]==nil) then
				el[k]=v
			end
		end
		
		return el,builder
	end,
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
	if (data==nil) webWarning("No data attached to download") return false,"No data attached to download"
	if (filename==nil) then
		filename=data:basename()
		data=rFetch(data)
		if (data==nil) then
			webWarning("Failed to download - download(data/filename,[filename])") return false,"Failed to download - download(data/filename,[filename])"
		end
	end
	page:download(data,filename)
	return true
end

local function urlToLocalStorage(url)
	path=cleanURL(url)
	path=path:gsub(":","_")
	path..="/"
	return path
end

local pageFunctions={
	localStorage={
		store=function(data,name)
			if (name==nil) then
				webWarning("localStorage.store(table,name)")
				return false
			end
			if (type(data)!="table") then
				webWarning("You can only store pods/tables")
				return false
			end
			if (name:ext()==nil) then
				name..=".pod"
			elseif (name:ext()!="pod") then
				name..=".pod"
			end
			
			local path=localStorageFolder..urlToLocalStorage(baseurl)
			mkdir(path)
			store(path..name,data)
			return true
		end,
		fetch=function(name)
			if (name:ext()==nil) then
				name..=".pod"
			elseif (name:ext()!="pod") then
				name..=".pod"
			end
			
			local path=localStorageFolder..urlToLocalStorage(baseurl)
			return fetch(path..name)
		end
	},
	dom={
		getElementById=getElementById,
		getElementsByClassName=getElementsByClassName,
		
		get=get,
		
		destroyElement=destroyElement,
		
		pushElement=pushElement,
		
		pushElementBelow=pushElementBelow,
		pushElementAbove=pushElementAbove,
		
		moveElementBelow=moveElementBelow,
		moveElementAbove=moveElementAbove,
		
		setStyle=setStyle,
		
		canvas={
			enter=function(element)
				if (cacheCanvas=="") cacheCanvas=get_draw_target()
				set_draw_target(element.screen)
				palt(0,true)
			end,
			exit=function()
				set_draw_target(cacheCanvas)
				palt(0,false)
				cacheCanvas=""
			end
		},
	},
	query={
		pack=packQuery,
		unpack=unpack
	},
	file={
		openPage=openRelativeTab,
		download=pageDownload,
	},
	attach={
		scripts=attachScripts,
		styling=attachStyling
	}
}

local permittedFunctions={
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
		description="Ability to create GUIs (buggy, not recommended)",
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
	networking={
		name="Networking",
		description="Sockets",
		risk=3,
		functions={
			socket=socket
		}
	}
}

local alwaysAllowedFunctions={
	--debug
	warn=webWarning,
	webwarn=webWarning,
	webWarn=webWarning,
	webWarning=webWarning,
	printh=sandboxedPrinth,
	
	--text input
	key=key,
	keyp=keyp,
	peektext=peektext,
	readtext=readtext,
	
	--controller input
	btn=btn,
	btnp=btnp,
	
	--graphical
	
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
	
	--variables
	
	select=select,
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
	
	--logic
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
	
	--info
	date=date,
	stat=stat,
	
	--page backend
	fetch=sandboxedFetch
}

for k,v in pairs(pageFunctions) do
	alwaysAllowedFunctions[k]=v
end

local function loadPermissions(environment,allowed)
	for i=1, #allowed do
		if (permittedFunctions[allowed[i]]) then
			for key,val in pairs(permittedFunctions[allowed[i]].functions) do
				environment[key]=val
			end
		end
	end
	--always allowed
	for key,val in pairs(alwaysAllowedFunctions) do
		environment[key]=val
	end
	return environment
end

--sandbox

local function buildEnvironment(permissions,data,pageData)
	local scriptEnvironment={}
	scriptEnvironment.__scroll={x=0,y=0}
	scriptEnvironment.__cursorData={x=0,y=0,rawx=0,rawy=0,b=0,wheelx=0,wheely=0,lb=0}
	scriptEnvironment.__lastCursorData={x=0,y=0,rawx=0,rawy=0,b=0,wheelx=0,wheely=0,lb=0}
	scriptEnvironment.__invertScrollX=data.invertScrollX or false
	scriptEnvironment.__invertScrollY=data.invertScrollY or false
	scriptEnvironment.__scrollSpeed=data.scrollSpeed or 8
	scriptEnvironment.__pageData=pageData
	scriptEnvironment.__viewport={width=0,height=0}
	--push defaults here
	scriptEnvironment.__styling={
		system={
			page={
				background=data.background or 7
			},
		},
		class={},
		id={},
		element={},
		defaultElement={
			title={margin_top=2,align="center",color=0,font=1,cursor=1},
			text={color=0,font=1,cursor=1},
			p8text={color=0,font=1,cursor=1},
			link={color=12,hovercolor=1,font=1,cursor="pointer",where="new",method="webpage",underline=true},
			input={color=7,background=1,dynamic_width=true,placeholder_color=6,cursor="edit",font=1,height=11},
			gap={height=11},
			canvas={}
		},
	}
	scriptEnvironment.__attachedScripts={} --unlisted
	scriptEnvironment.__attachedStyling={} --unlisted
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

page.getElementsByClassName = function(self,class)
    local res={}
    for i=1, #self.builtPage do
        local classes=self.builtPage[i].class or ""
        classes=classes:split(" ")
        for j=1, #classes do
            if (classes[j]==class) then
                add(res,editableElement(self.builtPage[i]))
            end
        end
    end
	
	return res
end

page.getDOM = function(self)
	local res={}
	for i=1, #self.builtPage do
		add(res,editableElement(self.builtPage[i]))
	end
	return res
end

page.getElementIndexById = function(self, id)
	local index=self.idLookup[id]
	if (not index) return nil
	
	return index
end

page.getRawElementById = function(self, id)
	local index=self:getElementIndexById(id)
	if (not index) return nil,nil
	local el = self.builtPage[index]
	if (not el) return nil,index --what
	
	return el,index
end

page.moveElementAbove = function(self,moving,still)
	local tbl={}
	local index
	if (moving and still) then
		for i=1, #self.builtPage do
		if (moving!=i) then
			if (still==i) then
				--push the moving element above
				add(tbl,self.builtPage[moving])
				index=#self.builtPage
			end
				add(tbl,self.builtPage[i])
			end
		end
	end
	self.builtPage=tbl
	pageDirty=true
	return index
end

page.moveElementBelow = function(self,moving,still)
	local tbl={}
	local index
	if (moving and still) then
		for i=1, #self.builtPage do
			if (moving!=i) then
				add(tbl,self.builtPage[i])
				if (still==i) then
					--push the moving element below
					add(tbl,self.builtPage[moving])
					index=#self.builtPage
				end
			end
		end
	end
	self.builtPage=tbl
	pageDirty=true
	return index
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
	pageDirty=true
	return obj,success,msg
end

page.pushElementAbove=function(self,obj,still,data)
	local elm=self:pushElement(obj,data)
	return editableElement(self:moveElementAbove(#self.builtPage,self:getElementIndexById(still)))
end

page.pushElementBelow=function(self,obj,still,data)
	local elm=self:pushElement(obj,data)
	return editableElement(self:moveElementBelow(#self.builtPage,self:getElementIndexById(still)))
end

page.setStyle=function(self,label,properties,replace)
	if (replace==nil) replace=false
	local typ="element"
	local label=label or ""
	if (label:sub(1,1)==".") then
		typ="class"
		label=label:sub(2)
	elseif (label:sub(1,1)=="#") then
		typ="id"
		label=label:sub(2)
	elseif (label:sub(1,2)=="__") then
		typ="system"
		label=label:sub(2)
	elseif (label=="") then
		typ="system"
		label="page"
	end
	
	if (replace) then
		self.env.__styling[typ][label]=properties
	else
		for k,v in pairs(properties) do
			self.env.__styling[typ][label][k]=v
		end
	end
	pageDirty=true
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
	return rip,meta,url
end

--cleanRip + metadata
page.extensiveRip=function(self,url)
	local rip,url=page:rip(url)
	if (rip==nil) return nil
	local start=url
	if (start:ext()!=nil) then
		start=start:sub(1,#start-#start:basename())
	end
	local meta={}
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

local sfetch=function() end

page.init=function(self,data)
	baseurl=data.url
	scripting=data.scripting
	local _
	webWarning=data.webWarning or printh
	self.env=buildEnvironment(data.permissions,data,self.pageData)
	rawset(self.env,"__url",baseurl)
	local _,query=baseurl:match("^([^?]*)%??(.*)$")
	rawset(self.env,"__query",query)
	rawset(self.env,"__queries",unpackQuery(query))
	self.pageData={width=0,height=0}
	self:setDisplay(data.width,data.height,false)
	sfetch=data.fetch or fetch
	ffetch=function(v,a)
		local data=sfetch(v,a)
		if (v==nil) then
			webWarning("Could not fetch "..v)
		end
		return data
	end
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
	exitCanvas() --ensure canvas is exited
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
	cls(self.env.__styling.system.page.background)
	drawPage(self.builtPage,ud)
	exitCanvas() --ensure canvas is exited
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
return page,"2.3"
