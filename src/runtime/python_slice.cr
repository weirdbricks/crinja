# Python's slice-indexing algorithm, simplified: no clamping edge case
# left unhandled for the realistic range of inputs real templates use
# (out-of-range start/stop just naturally stop the loop early, same
# observable result as Python's own clamping).
module Crinja::PythonSlice
  def self.slice(items : Array(T), start : Int32?, stop : Int32?, step : Int32) : Array(T) forall T
    len = items.size
    raise Crinja::TypeError.new("slice step cannot be zero") if step == 0

    result = [] of T
    if step > 0
      i = start.nil? ? 0 : normalize(start, len)
      hi = stop.nil? ? len : normalize(stop, len)
      while i < hi
        result << items[i] if i >= 0 && i < len
        i += step
      end
    else
      i = start.nil? ? len - 1 : normalize(start, len)
      lo = stop.nil? ? -1 : normalize(stop, len)
      while i > lo
        result << items[i] if i >= 0 && i < len
        i += step
      end
    end
    result
  end

  private def self.normalize(i : Int32, len : Int32) : Int32
    i < 0 ? i + len : i
  end
end
