--!strict
-- NumberFormat Module
-- Handles number formatting, abbreviations (k, M, B), currency formatting, and playtime/countdown formatting.

local NumberFormat = {}

-- Formats a number with comma separators (e.g. 1000 -> "1,000", 1234567 -> "1,234,567")
function NumberFormat.commas(n: number | string): string
	local num = math.floor(tonumber(n) or 0)
	local s = tostring(num)
	local sign = ""
	if string.sub(s, 1, 1) == "-" then
		sign = "-"
		s = string.sub(s, 2)
	end
	while true do
		local replaced, count = string.gsub(s, "^(%d+)(%d%d%d)", "%1,%2")
		s = replaced
		if count == 0 then
			break
		end
	end
	return sign .. s
end

-- Compact number format (e.g. 950 -> "950", 15200 -> "15.2k", 2500000 -> "2.5M")
function NumberFormat.compact(n: number | string): string
	local num = math.floor(tonumber(n) or 0)
	local sign = num < 0 and "-" or ""
	num = math.abs(num)

	if num < 10000 then
		return sign .. NumberFormat.commas(num)
	elseif num < 1000000 then
		local k = num / 1000
		local s = string.format("%.1f", k)
		s = string.gsub(s, "%.0$", "")
		return sign .. s .. "k"
	elseif num < 1000000000 then
		local m = num / 1000000
		local s = string.format("%.1f", m)
		s = string.gsub(s, "%.0$", "")
		return sign .. s .. "M"
	else
		local b = num / 1000000000
		local s = string.format("%.1f", b)
		s = string.gsub(s, "%.0$", "")
		return sign .. s .. "B"
	end
end

-- Formats a number as currency (e.g. "$1,250" or "$15.2k")
function NumberFormat.currency(n: number | string, useCompact: boolean?): string
	if useCompact then
		return "$" .. NumberFormat.compact(n)
	else
		return "$" .. NumberFormat.commas(n)
	end
end

-- Formats playtime requirement in minutes (e.g. 15 -> "15m", 60 -> "1 hr", 90 -> "1 hr 30 min", 120 -> "2 hrs")
function NumberFormat.formatPlaytimeRequirement(mins: number | string): string
	local totalMins = math.floor(tonumber(mins) or 0)
	if totalMins < 60 then
		return tostring(totalMins) .. "m"
	else
		local h = math.floor(totalMins / 60)
		local m = totalMins % 60
		local hrText = (h == 1) and "1 hr" or (h .. " hrs")
		if m == 0 then
			return hrText
		else
			return string.format("%s %d min", hrText, m)
		end
	end
end

-- Formats played duration in seconds into readable text
-- e.g. 45 -> "45 sec", 750 -> "12 min 30 sec", 3665 -> "1 hr 1 min 5 sec"
function NumberFormat.formatPlaytimePlayed(seconds: number | string): string
	local sec = math.max(0, math.floor(tonumber(seconds) or 0))
	local h = math.floor(sec / 3600)
	local m = math.floor((sec % 3600) / 60)
	local s = sec % 60

	if h >= 1 then
		local hrText = (h == 1) and "1 hr" or (h .. " hrs")
		if m > 0 then
			return string.format("%s %d min %d sec", hrText, m, s)
		else
			return string.format("%s %d sec", hrText, s)
		end
	elseif m >= 1 then
		return string.format("%d min %d sec", m, s)
	else
		return string.format("%d sec", s)
	end
end

-- Standard digital timer format HH:MM:SS or MM:SS
function NumberFormat.formatTime(seconds: number | string): string
	local sec = math.max(0, math.floor(tonumber(seconds) or 0))
	local h = math.floor(sec / 3600)
	local m = math.floor((sec % 3600) / 60)
	local s = sec % 60
	if h > 0 then
		return string.format("%02d:%02d:%02d", h, m, s)
	else
		return string.format("%02d:%02d", m, s)
	end
end

return NumberFormat
