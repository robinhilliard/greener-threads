> So, @robinhilliard has essentially build an operating system kernel in #cfml. My head explodes. (Kai Koenig @agentK  2 Nov 2012)

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

Here's a few code listings to give you an idea what the component does. It takes a simple, limited syntax cfscript component:

*HelloWorldLogger.cfc*
```
 component {
    function sayHello() {
       var countDown = 3;
       var j = 0;      
       for (j=countDown; j gt 0; j--)
          writeLog("#getTid()#: #j#");         
       writeLog("#getTid()#: Hello #getPlace()#");      
    }   
    function getPlace(String place = "Kernel World") {
       return place; 
    }
 }
```
and rewrites it like this:

*gt_HelloWorldLogger_373418B4DB9FACC28E77B78A46791D21.cfc*
```
 component extends="HelloWorldLogger" {
    public void function _gt_init(thread, context) {
       _gt = new GreenerThread(this);
       _gt.setSymbolLocations(
          block_1 = 1,
          block_2 = 5,
          block_3 = 13,
          getPlace = 13,
          sayHello = 5
       );
       if (not isNumeric(thread.stack[1].pc[1])) thread.stack[1].pc[1] = _gt.getSymbolLocation(thread.stack[1].pc[1]);
       _gt.setContext(thread, context);
    }
    private struct function _gt_args_getPlace(String place = "Kernel World") {return arguments;}
    private struct function _gt_args_sayHello() {return arguments;}
    public function _gt_getSymbol(string symbol) {return _gt.getSymbolLocation(symbol);}
    public boolean function _gt_step() {
       var j = 0;var countDown = 0;
       structAppend(local, _gt.getFrameLocalVariables());
       switch(_gt.getPc()) {
          case 1: _gt.setReturnValue(1, _gt.getTid()); _gt.incPc(); break;
          case 2: writeLog("# _gt.getReturnValue(1) #: #j#"); _gt.incPc(); break;
          case 3: j--; _gt.incPc(); break;
          case 4: _gt.popPc(); break;
          case 5: countDown = 3; _gt.incPc(); break;
          case 6: j = 0; _gt.incPc(); break;
          case 7: j=countDown; _gt.incPc(); break;
          case 8: if (j gt 0) _gt.pushPc(_gt.getSymbolLocation("block_1")); else _gt.incPc(); break;
          case 9: _gt.setReturnValue(4, _gt.getTid()); _gt.incPc(); break;
          case 10: _gt.incPc(); _gt.pushStackFrame(5, _gt.getSymbolLocation("getPlace"), _gt_args_getPlace()); break;
          case 11: writeLog("# _gt.getReturnValue(4) #: Hello # _gt.getReturnValue(5) #"); _gt.incPc(); break;
          case 12: _gt.popPc(); break;
          case 13: _gt.popStackFrame(place); break;
          default: return false;   
       }
       _gt.saveLocalVariables(local);      
       return _gt.threadHasStackFrames();
    }
 }
```
You could then start lots of them running at once like this:
```
    helper = new GreenerThread();
    helper.start(8);                      // Start worker threads
    helper.setPaused(true);               // Pause (optional)
    for (i = 30000; i gt 0; i--)
       helper.spawn("HelloWorldLogger", "sayHello");   // Create a green thread   
    helper.setPaused(false);              // Unpause (optinal)
    sleep(60000);                         // Wait
    helper.stop();                        // Stop worker threads
```
Or run (another example) one step at a time like this:
```
 <cfscript>
    if (not structKeyExists(url, "step")) {
       helper = new GreenerThread();                // get an instance of the library
       helloWorld = helper.greenify("HelloWorld");  // compile and return instance of "greener" component   
       session.greenThread = {
          tid = 1,                                  // thread id
          name = "",                                // optional name
          messageQueue = [],                        // messages for thread
          stack = [{
             instance = helloWorld,                 // the component instance
             localVars = {arguments = {}},          // local variables including arguments
             returnValues = [],                     // registers to record values returned from calls
             returnCallIndex = 0,                   // the register index to record our return value in our parent stack frame (if any)
             pc = ["sayHello"]                      // starting location, in this case a symbol pointing to start of test method
          }]
       };
       helloWorld._gt_init(session.greenThread, helper);   // pass references to thread and helper to our instance
    }
    if(arrayIsEmpty(session.greenThread.stack))            // stack empty
       abort;   
 </cfscript>
 <hr/><a href="?step">Step</a><hr/>
 <cfdump format="text" label="session.greenThread" var="#session.greenThread#">
 <cfset session.greenThread.stack[1].instance._gt_step()>
```
And look at a stack dump:


```
session.greenThread Struct
 messageQueue Array
 name string
 SAVELOCALVARSTOFRAME number 1
 stack Array
     1 Struct
         instance Component (gt_HelloWorld_CD9A704A921EBC9E1888F7C55B913135)
         localVars Scope
             arguments Struct
             COUNTDOWN number 3
             J number 3
         pc Array
             1 number 1
             2 number 7
         returnCallIndex number 0
         returnValues Array
 tid number 1
 ```
 This spectacular, dangerously teetering presentation and accompanying code have been tested in CF9 and Railo 4. Did I mention this is an experiment?