<cfsetting requesttimeout="999" >

<cfscript>

	helper = new GreenerThread();
	helper.start(8);									// Start worker threads
	helper.setPaused(true);								// Pause (optional)
	
	for (i = 30000; i gt 0; i--)
		helper.spawn("HelloWorldLogger", "sayHello");	// Create a green thread
	
	helper.setPaused(false);							// Unpause (optinal)
	sleep(60000);										// Wait
	helper.stop();										// Stop worker threads
	
</cfscript>