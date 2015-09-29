<cfscript>

	if (not structKeyExists(url, "step")) {
		
		helper = new GreenerThread();						// get an instance of the library
		messages = helper.greenify("Messages");			// compile and return instance of "greener" component
			
		session.greenThread = {
			tid = 1,										// thread id
			name = "",										// optional name
			messageQueue = [],								// messages for thread
			stack = [{
				instance = messages,						// the component instance
				localVars = {arguments = {}},				// local variables including arguments
				returnValues = [],							// registers to record values returned from calls
				returnCallIndex = 0,						// the register index to record our return value in our parent stack frame (if any)
				pc = ["sayHello"]								// starting location, in this case a symbol pointing to start of test method
			}]
		};
	
		messages._gt_init(session.greenThread, helper);		// pass references to thread and helper to our instance
	
	}
	
	if (structKeyExists(url, "send"))
		arrayAppend(
		session.greenThread.messageQueue, url.send);		// Add a message to the queue
	
	if(arrayIsEmpty(session.greenThread.stack))				// stack empty
		abort;	
	
</cfscript>

<hr/><a href="?step">Step</a> | <a href="?send=CFObjective&step">Send and Step</a><hr/>
<cfdump label="session.greenThread" var="#session.greenThread#">
<cfset session.greenThread.stack[1].instance._gt_step()>