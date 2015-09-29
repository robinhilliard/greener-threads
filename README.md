How would you write programs in CFML if threads were really, really cheap?

An Erlang VM can run tens of thousands of threads at once - writing a long polling web page is trivial in Erlang because you don't really care if the request thread is blocked for hours, or even overnight - you just write it like any other synchronous web request and let it wait when it has to.

At CFObjective ANZ in 2012 I was planning a presentation on the differences between CFML and Erlang programming. I thought I'd approach it by trying to do things Erlang was good at in CFML, and then showing how Erlang solved that particular problem. I started with the point about threads, things sort of got out of control and I wound up with this library - oops.

Greener Threads is a CFC that parses a basic cfscript component, slicing it up into blocks, then expressions and finally individual function calls (a sort of CFML assembly language); generates a weird subclass of the original component that can be called one 'chunk' at a time (a big switch statement that the program counter variable indexes), and provides a 'kernel' that can use a worker pool of a few CF (Java) threads to run 10s of 1,000s of these chopped up components concurrently. The stack and program counters for each thread are maintained in normal CF structures that you can dump out and watch as you step through the program.

A .cfm slide deck is included that calls some of the examples, letting you step through a running thread with cfdump and start 30,000 threads for a minute, just because we can. There is also a slide showing the parser in action.

This is not production code - it is an experiment. You will find it interesting if you:

- Want to understand what a thread looks like from inside of a VM or operating system (it will really help with an understanding of locking and shared scopes) without having to learn C
- Are interested in parsing cfscript code, and want to see one approach to doing it
- Think it would be cool to be able to run some code, pause it, save its stack in some JSON, bring it back a few days later and keep running it, just like pausing VMWare, but all in CFML

I actually think that last point shows a lot of promise as a simple way to write long running workflows with asynchronous steps in them (waiting for an email reply for example) - the whole workflow could be written as a single synchronous function that gets hibernated every time it needs to wait for some input.

The wiki contains some listings of an original component; what it looks like when rewritten; how to spawn lots of threads; how to spawn a single thread and step through it, and what a dump of the 'stack' looks like.

Tested in CF9 and Railo 4.