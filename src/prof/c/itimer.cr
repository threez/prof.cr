require "c/sys/time"

lib LibC
  {% unless flag?(:solaris) %}
    SIGPROF = 27
  {% end %}

  ITIMER_REAL    = 0
  ITIMER_VIRTUAL = 1
  ITIMER_PROF    = 2

  struct Itimerval
    it_interval : Timeval
    it_value : Timeval
  end

  fun setitimer(which : Int, value : Itimerval*, ovalue : Itimerval*) : Int
  fun getitimer(which : Int, value : Itimerval*) : Int
end
