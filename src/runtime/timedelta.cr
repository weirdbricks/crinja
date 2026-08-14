require "./value"
require "../object"

# Python's `datetime.timedelta`, modeled only as far as the real roles
# that hit it need: a signed difference held as a total second count, with
# `days`/`seconds`/`microseconds` attributes and a `total_seconds()` method.
# Created by the `-` operator when both operands are `Time` values (real
# Ansible's `to_datetime(...) - to_datetime(...)` idiom, e.g. dev-sec
# os_hardening's password-ageing day-count assert reading `.days` off the
# result). Only non-negative differences are expected in practice (an
# earlier date subtracted from a later one), matching crystal-ansible's own
# hand-rolled timedelta; a negative span is not normalized like Python's
# truncating `timedelta.days` would.
class Crinja::TimeDelta
  include Crinja::Object

  getter seconds : Int64

  def initialize(@seconds : Int64)
  end

  # Whole days, truncated toward zero (matches Python's timedelta.days for
  # the non-negative spans real usage produces).
  def days : Int64
    @seconds // 86_400
  end

  def total_seconds : Float64
    @seconds.to_f64
  end

  def crinja_attribute(attr : Crinja::Value) : Crinja::Value
    case attr.to_string
    when "days"
      Crinja::Value.new(days)
    when "seconds"
      Crinja::Value.new(@seconds % 86_400)
    when "microseconds"
      Crinja::Value.new(0)
    else
      Crinja::Value.new(Crinja::Undefined.new(attr.to_s))
    end
  end

  def crinja_call(name : String) : Crinja::Callable | Crinja::Callable::Proc | Nil
    return nil unless name == "total_seconds"
    ->(arguments : Crinja::Arguments) { Crinja::Value.new(total_seconds) }.as(Crinja::Callable::Proc)
  end

  # Python's `str(timedelta)`: "X day(s), HH:MM:SS" (day part omitted for
  # a sub-day delta). Good enough for the rare render of a bare timedelta;
  # real usage reads `.days`/`.total_seconds()` instead.
  def to_s(io : IO) : Nil
    days = self.days
    remainder = @seconds - (days * 86_400)
    hours = remainder // 3600
    minutes = (remainder % 3600) // 60
    secs = remainder % 60
    if days > 0
      io << days << (days == 1 ? " day, " : " days, ")
    end
    io << hours << ':' << (minutes < 10 ? "0" : "") << minutes << ':' << (secs < 10 ? "0" : "") << secs
  end
end
