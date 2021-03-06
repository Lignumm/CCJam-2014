local function require(file)
	return dofile(shell.resolve(file))
end

local function startsWith(str, start)
	return str:sub(1, #start) == start
end

local function removeRespectQuote(str, ch, replacement)
	local inQuote = false
	local newStr = ""
	for i=1,#str do
		local c = str:sub(i, i)
		if c == '"' then inQuote = not inQuote end
		if inQuote and c == ch then
			newStr = newStr .. (replacement or ch)
		elseif c ~= ch then
			newStr = newStr .. c
		end
	end
	return newStr
end

local function isEmpty(line)
	return line:match("^%s-$") ~= nil
end

local function fixCommas(str)
	local inQuote = false
	local newStr = ""
	for i=1,#str do
		local c = str:sub(i, i)
		if c == '"' then inQuote = not inQuote end
		if inQuote and c == ',' then
			newStr = newStr .. string.char(6)
		else
			newStr = newStr .. c
		end
	end
	return newStr
end

local function trim(str)
	return str:gsub("^%s+", "")
end

local Lexer = {}
Lexer.__index = Lexer

function Lexer.new()
	local self = setmetatable({}, Lexer)
	self.parseTree = {}
	return self
end

function Lexer:parseFunctionCall(funcCall, depth, lineNum)
	local pkg, callInfo = funcCall:match("(%w+):(.+)")
	callInfo = trim(callInfo)
	
	local tbl = { ["type"] = "call", ["pkg"] = pkg, funcs = {} }
	
	local function parseCallInfo(info)
		info = removeRespectQuote(info, ' ')
		local funcTable = {}
		
		for call in info:gmatch("[^;]+") do
			local paramsTable = {}
			local name,params,repetition = call:match("(%w+)%s-%[(.-)]%s-%*?%s-(%d*)")
			
			params = fixCommas(params)
			params = removeRespectQuote(params, ' ')
			
			for param in params:gmatch("[^,]+") do
				table.insert(paramsTable, param)
			end
			
			table.insert(funcTable, {
				["name"] = name,
				["params"] = paramsTable,
				["repetition"] = tonumber(repetition)
			})
		end
		
		return funcTable
	end
	
	tbl["funcs"] = parseCallInfo(callInfo)
	tbl["depth"] = depth
	tbl["line"] = lineNum
	return tbl
end

function Lexer:getFunctionCall(line)
	local call = line:match("%w+:.+")
	return call
end

function Lexer:parseLabel(line, depth, lineNum)
	local name = line:match("(%w+):")
	local tbl = { 
		["name"] = name,
		["depth"] = depth,
		["line"] = lineNum,
		["type"] = "label"
	}
	return tbl
end

function Lexer:getLabel(line)
	local label = line:match("%w+:%s-$")
	return label
end

function Lexer:getStatement(line)
	local statement = line:match("%w+%s-{%s-.-%s-}")
	return statement
end

function Lexer:parseStatement(line, depth, lineNum)
	local type, condition = line:match("(%w+)%s-{%s-(.-)%s-}")
	condition = removeRespectQuote(condition, ' ')
	
	if self:getFunctionCall(condition) then
		condition = self:parseFunctionCall(condition)
	end
	
	local tbl = { 
		["type"] = "statement", 
		["kind"] = type, 
		["condition"] = condition,
		["depth"] = depth,
		["line"] = lineNum
	}
	return tbl
end

function Lexer:clear()
	self.parseTree = {}
end

function Lexer:getLineDepth(line)
	local depth = 0
	
	for i=1,#line do
		local c = line:sub(i, i)
		if c == '\t' or c == ' ' then
			depth = depth + 1
		else
			return depth
		end
	end
end

function Lexer:findFunctionSpace(parent, depth)
	for i=#parent,1,-1 do
		if parent[i].depth < depth then
			if parent[i].body == nil then
				parent[i].body = {}
			else
				local attempt = self:findFunctionSpace(parent[i].body, depth)
				if attempt ~= nil then
					return attempt
				end
			end

			return parent[i].body
		end
	end
end

function Lexer:tokenise(str)
	-- Please do prepare for incredible hardcoding.
	-- But it's a jam, so it's alright ;).
	
	local lineCount = 0
	local previousDepth = 0
	
	for line in str:gmatch("[^\n]+") do
		lineCount = lineCount + 1
		
		local okay, err = pcall(function()
			if not isEmpty(line) and not startsWith(line, "//") and not startsWith(line, "#") and not startsWith(line, "--") then		
				local tbl = nil
				local depth = self:getLineDepth(line)

				if depth == 0 then
					tbl = self.parseTree
				else
					tbl = self:findFunctionSpace(self.parseTree, depth)
					
					if tbl == nil then
						error("no matching statement", 0)
					end
				end
	
				local statement = self:getStatement(line)
				if statement then
					table.insert(tbl, self:parseStatement(line, depth, lineCount))
					return
				end
				
				local label = self:getLabel(line)
				if label then
					table.insert(tbl, self:parseLabel(line, depth, lineCount))
					return
				end
				
				local call = self:getFunctionCall(line)
				if call then
					table.insert(tbl, self:parseFunctionCall(line, depth, lineCount))
					return
				end
				
				error("syntax error", 0)
			end
		end)
		
		if not okay then
			return lineCount .. ": " .. err
		end
	end
end

return Lexer