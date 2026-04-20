# Update from 0.15.2 to 0.16.0
## Things changed
Whether it affects this build or not.

cImport is moving to the build system rather than being a language built-in.

You can also use this...
https://codeberg.org/ziglang/translate-c

@Type is deprecated (for reifying types) and replaced with more specific versions like @Int.

I/O as an Interface

Io.Threaded calls IO ops like read and write directly. It includes cancellation.

Io.Evented is WIP and includes M:N (Green threads).

Everything needs an io to do io. Io means anything non-deterministic or blocking.

error.Canceled is returned when an io operation is cancelled.

Things have changed to adhere to the Io system, for example Thread and File operations.

file.close() becomes file.close(io).

PriorityQueue and PriorityDequeue are now 'unmanaged' and the managed version is gone.





