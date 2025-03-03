export type callback<T> = (T) -> ()
export type Case_T<T> = {
	[T]: callback<T>,
}

local mt = {}

mt.__index = function(self, k)
	if not rawget(self, k) then
		local def = rawget(self, "__default")
		if def then
			return def
		end
	else
		return rawget(self, k)
	end

	return nil
end

return function<T>(n: T)
	return function(cases: Case_T<T>)
		setmetatable(cases, mt)
		local func = cases[n]

		if func then
			local val = func(n) :: any

			return val
		end

		return nil
	end
end
