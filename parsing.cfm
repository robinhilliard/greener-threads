<cfscript>

	helper = new GreenerThread();						// get an instance of the library
	helper.debug = true;
	helloWorld = helper.greenify("HelloWorld", true);	// compile and return instance of "greener" component
		
</cfscript>