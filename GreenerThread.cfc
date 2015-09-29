/**
 *	Run limited-script-syntax cfcs in a simulated multi-tasking kernel

 *	(c) 2012 RocketBoots Pty Limited

 *	This program is free software: you can redistribute it and/or modify
 *	it under the terms of the GNU General Public License as published by
 *	the Free Software Foundation, either version 3 of the License, or
 *	(at your option) any later version.
 *	
 *	This program is distributed in the hope that it will be useful,
 *	but WITHOUT ANY WARRANTY; without even the implied warranty of
 *	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *	GNU General Public License for more details.
 *	
 *	You should have received a copy of the GNU General Public License
 *	along with this program.  If not, see <http://www.gnu.org/licenses/>.

 * 	$Id: GreenerThread.cfc 9575 2012-11-02 01:01:12Z robin $
 */
 
component {

	this.debug = false;

	// PUBLIC //
	
	// Functions for creating and running cfcs in a simulated multi-tasking kernel
	
	
	/**
	 * Constructor used by greenified components to pass reference to themselves for use
	 * by the package helper methods
	 */
	 
	public function init(instance = 0) {
		if (not isSimpleValue(instance))
			_instance = instance;
	}
	
	
	
	/**
	 * Rewrite component in green threads version and return an instance
	 * Source files are created with a "_gt" prefix in the same directory
	 * as this component
	 *
	 * @param componentName		Name as you would pass to createObject
	 * @param forceRecompile	Always regenerate component
	 * @returns					green instance of component
	 */
	 
	public function greenify(string componentName, boolean forceRecompile = false) {
		var oldSource = fileRead(getMetaData(createObject("component", componentName)).path);
		var outputDirectory = getDirectoryFromPath(getCurrentTemplatePath());
		var newClassName = "gt_" & componentName & "_" & hash(oldSource);
		var newFilePath = outputDirectory & "/" & newClassName & ".cfc";
		var newSource = 0;
		
		if (forceRecompile or not fileExists(newFilePath)) {
		
			newSource = writeComponent(parseComponent(oldSource), componentName);
			fileWrite(newFilePath, newSource);
			fileSetAccessMode(newFilePath, "777");
			
		}
			
		return createObject("component", newClassName);
	}
	
	
	
	/**
	 * Start a "kernel" to run green threads in worker CF threads
	 *
	 * @param numWorkers	Number of worker threads, should ideally be same as number of cores
	 */
	 
	public void function start(numeric numWorkers = 1) {
		_threadsByTid = {};		// Map
		_threadsByName = {};	// Map, by optional name parameter passed to spawn()
		_threadsByWorker = [];	// 2D array
		_run = true;
		_paused = false;
		_context = this;
		_nextTaskedWorker = 1;
		_nextTid = 1;
		
		param name="this.uid" default="#createUUID()#";  
		
		while (numWorkers gt 0) {
			
			_threadsByWorker[numWorkers] = [];
			
			thread action="run" name="#_context.uid#_worker_#numWorkers#" workerIndex="#numWorkers#" {
				this._worker(workerIndex);
			}
			
			numWorkers--;
		}
		
	}
	
	
	
	/**
	 * Execute worker thread. This is only public so that it can be invoked via the "this" scope
	 * to preserve implicit variables scope behaviour
	 *
	 * @param workerIndex	index used to access our thread list
	 */
	 
	public void function _worker(numeric workerIndex) {
		var thisWorker = workerIndex;
		var myThreads = 0;
		var threadIndex = 0;
		var nextThread = 0;
		
		writeLog("worker #workerIndex# started");
		
		try {
		
			while (_run) {
				
				// TODO: Improve locking of myThreads - relatively safe atm as we are only thread to delete from this array
				
				myThreads = _threadsByWorker[thisWorker];
				
				if (not _paused and not arrayIsEmpty(myThreads)) {
					
					for (threadIndex = arrayLen(myThreads); threadIndex gt 0; threadIndex--) {
						
						nextThread = myThreads[threadIndex];
						
						if (arrayLen(nextThread.stack) eq 0) {	
							
							// Run out of stuff to do, kill thread
							arrayDeleteAt(myThreads, threadIndex);
							
							lock name="#this.uid#_threads" type="exclusive" timeout="1" throwontimeout="false" {   
								 
								structDelete(_threadsByTid, nextThread.tid);
								
								if (nextThread.name neq "") {
									structDelete(_threadsByName, nextThread.name);
								}
							}	// lock
							
						} else {
							nextThread.stack[1].instance._gt_step(); // Let the thread execute the next step
						}
					} // for each thread
					
				} else {
					sleep(1);
					
				} // myThreads not empty
			} // while run 
		
		} catch(any e) {
			writeDump(e, "console");
		}
		
		writeLog("worker #workerIndex# stopped");
		
	}
	
	
	
	/**
	 * Stop "kernel"
	 */
	 
	public void function stop() {
		_run = false;
		sleep(100);		// TODO: join or otherwise ensure workers have stopped
	}
	
	
	
	/**
	 * Pause workers processing threads without shutting them down
	 *
	 * @param paused 	boolean
	 */
	 
	public void function setPaused(boolean paused) {
		_paused = paused;
	}
	
	
	
	/**
	 * Run a green component instance in the "kernel"
	 *
	 * @param componentName	passed to greenify()
	 * @param method		method to call
	 * @param namedArgs		arguments to pass to method
	 * @returns				new thread tid
	 */
	 
	public string function spawn(string componentName = "", string method, struct namedArgs = {}, threadName = "") {
		var instance = greenify(componentName);
		var newThread = 0;
		var newTid = 0;
		var newWorker = 0;
		
		lock name="#this.uid#_spawn" type="exclusive" timeout="1" throwontimeout="true" { 
			newTid = _nextTid++;
			newWorker = (_nextTaskedWorker++ mod arrayLen(_threadsByWorker)) + 1;
		}
		
		namedArgs.arguments = structCopy(namedArgs); // TODO: positional arguments (requires additional metadata in generated component)
		
		newThread = {
			tid = newTid,
			name = threadName,
			messageQueue = [],
			stack = [{
				instance = instance,
				localVars = namedArgs,
				returnValues = [],
				returnCallIndex = 0,
				pc = [method]
			}]
		};
		
		instance._gt_init(newThread, this);
		
		lock name="#this.uid#_threads" type="exclusive" timeout="1" throwontimeout="false" { 
			if (threadName neq "") {
				_threadsByName[threadName] = newThread;
			}
			
			_threadsByTid[newTid] = newThread;
			arrayAppend(_threadsByWorker[newWorker], newThread);
		}
		
		return newTid;
		
	}
	
	
	
	
	
	
	// PACKAGE //
	
	// Most of these functions are helpers called by gt_step() when GreenerThreads is being used as a per-instance utility
	// Rewritten components are saved in the same directory as GreenerThreads so that they can access package scope
	
	
	
	/**
	 * Set the thread and context for the other package methods to work with, called at the start of _gt_step()
	 *
	 * @param thread	reference to structure containing thread stack and other details
	 * @param context	the main instance of GreenerThreads managing all threads
	 */
	 
	package void function setContext(struct thread, GreenerThread context) {
		_thread = thread;
		_context = context;
	}
	
	
	
	/**
	 * Set a list of symbol/program counter pairs. This call is generated by writeComponent()
	 *
	 * @param	symbol=pc, ...
	 */
	 
	package void function setSymbolLocations() {
		_symbols = arguments;
	}
	
	
	
	/**
	 * Called by _gt_step() to lookup the program counter for a symbol registered with setSymbolLocations()
	 *
	 * @param	symbol	Name of symbol to lookup
	 * @returns			Corresponding program counter or 0 if no such counter
	 */
	 
	package function getSymbolLocation(string symbol) {
		if (structKeyExists(_symbols, symbol))
			return _symbols[symbol];
		else
			return 0;
	}
	
	
	
	/**
	 * Called by _gt_step() to cause a new stack frame to be created on the thread passed to setThread()
	 *
	 * @param	callIndex	The call to save any returned values against
	 * @param	initialPc	Starting program counter
	 * @param	args		Arguments to pass to function - they will all be named after passing through
	 *						the _gt_{function name} methods
	 */
	 
	package void function pushStackFrame(numeric callIndex, numeric initialPc, struct args) {
		
		args.arguments = structCopy(args);
		
		arrayInsertAt(_thread.stack, 1, {
			instance = _instance,			// TODO: support green to green method invocation
			localVars = args,
			returnValues = [],
			returnCallIndex = callIndex,
			pc = [initialPc]
		});
		
		_thread.saveLocalVarsToFrame = 2; 	// saveLocalVariables() will save to second frame on stack
	}
	


	/**
	 * Called by _gt_step() to remove the current stack frame and set a return value in parent frame if provided
	 *
	 * @param returnCallValue	The value to return to the parent frame in the returnCallIndex position
	 */
	 
	package void function popStackFrame(returnCallValue) {
		
		if (structKeyExists(arguments, "returnCallValue")) {
			_thread.stack[2].returnValues[_thread.stack[1].returnCallIndex] = returnCallValue;
		}
		
		arrayDeleteAt(_thread.stack, 1);
		_thread.saveLocalVarsToFrame = 0;	// don't save local variables
	}
	
	
	
	/**
	 * Called to check that thread is still running
	 */
	
	package boolean function threadHasStackFrames() {
		return arrayLen(_thread.stack) gt 0;
	}
	
	
	
	/**
	 * Set a return value in the current frame
	 *
	 * @param	index	Index of value to set determined by writeComponent()
	 * @param	value	Return value
	 */
	 
	package void function setReturnValue(numeric index, value) {
		_thread.stack[1].returnValues[index] = value;
	}
	
	
	
	/**
	 * Retrieve a return value set earlier
	 *
	 * @param	index	Index of value to retrieve determined by writeComponent()
	 * @returns			The value
	 */
	 
	package function getReturnValue(numeric index) {
		return _thread.stack[1].returnValues[index];
	}
	
	
	
	/**
	 * Get thread Id
	 */
	 
	package function getTid() {
		return _thread.tid;
	}
	
	
	
	/**
	 * Get current program counter
	 */
	 
	package numeric function getPc() {
		return _thread.stack[1].pc[1];	
	}
	
	
	
	/**
	 * Called by _gt_step() to increment the program counter of the current stack frame
	 */
	 
	package void function incPc() {
		_thread.stack[1].pc[1]++;
	}


	
	/**
	 * Called by _gt_step() to jump to a block (used for if/while/etc) without changing stack frame
	 *
	 * @param pc	Program Counter to jump to
	 */
	
	package void function pushPc(numeric pc) {
		arrayInsertAt(_thread.stack[1].pc, 1, pc);
	}	


	
	/**
	 * Called by _gt_step() to return from a block to previous position without changing stack frame
	 * If we've run out of blocks to return to, pop the stack frame
	 *
	 * @param pc	Program Counter to jump to
	 */
	
	package void function popPc(numeric pc) {
		
		if (arrayLen(_thread.stack[1].pc) eq 1) {
			popStackFrame();
			
		} else {
			arrayDeleteAt(_thread.stack[1].pc, 1);
			
		}
	}	
	
	
	
	/**
	 * Called by _gt_step() to save local variables after executing a statement
	 *
	 * @param	localScope	struct containing variables to save
	 */
	 
	package void function saveLocalVariables(struct localScope) {
		if (arrayLen(_thread.stack) gt 0 and _thread.saveLocalVarsToFrame gt 0) {
			structDelete(localScope, "this");
			_thread.stack[_thread.saveLocalVarsToFrame].localVars = localScope;
		}
	}
	
	
	
	/**
	 * Called by _gt_step() to restore local variables before executing a statement
	 *
	 * @returns struct containing local variables to append to local
	 */
	 
	package struct function getFrameLocalVariables() {
		_thread.saveLocalVarsToFrame = 1;
		return _thread.stack[_thread.saveLocalVarsToFrame].localVars;
	}
	
	
	
	/**
	 * writeComponent() replaces struct literals with calls to this function in _gt_step()
	 */
	 
	package struct function structLiteral() {
		return arguments;
	}
	
	
	
	/**
	 * Send a message to another thread. 
	 *
	 * @param	tid		Unique thread id to send message to
	 * @param 	message	Arbitrary object to send as a message
	 * @throws			INVALID_TID
	 */
	 	
	package void function send(string tid, message) {
		
		param name="_context.uid" default="#createUUID()#"; 
		
		if (not structKeyExists(_context.threads, tid)) {
			throw(errorCode = "INVALID_TID", message = "no thread with tid #tid#");
			
		} else {
			lock name="#_context.uid#_#_thread.tid#_queue" type="exclusive" timeout="1" throwOnTimeout = true {
				arrayAppend(_context.threads[tid].queue, message);
			}
		}
	}
	
	
	
	/**
	 * Block until there is a message in the queue, then return it. I tried very hard to get a more
	 * Erlang-y message handling system, but I've had to surrender for the time being and make do with
	 * implementing switch()
	 *
	 * @param callResultIndex Index to pass to setReturnValue when a message is received
	 */
	 
	package function receive(numeric callResultIndex) {
		var newMessage = 0;
		
		param name="_context.uid" default="#createUUID()#"; 
		_thread.recieveResultIndex = callResultIndex;
		
		lock name="#_context.uid#_#_thread.tid#_queue" type="exclusive" timeout="1" throwOnTimeout = true {
			if (not arrayIsEmpty(_thread.messageQueue)) {
				newMessage = _thread.messageQueue[1];
				arrayDeleteAt(_thread.messageQueue, 1);
				incPc();
				setReturnValue(_thread.recieveResultIndex, newMessage);
			}
		}
	}
	
	
	
	
	
	
	// PRIVATE //
	
	// Methods for parsing and rewriting components so that they can run in the kernel
	
	
	
	/**
	 * Given the source of a component, break it up into blocks, statements and function calls so that it can be re-arranged
	 * TODO: else, switch/case, try/catch, escaping string contents
	 *
	 * @param	src	Source of component in cfscript style. Custom tags with bodies, else, switch/case, try/catch and
	 *				valid code inside strings are not currently supported. The _gt prefix is reserved for our use
	 * @returns		A structure containing source, blocks, calls and declarations
	 */
	 
	private struct function parseComponent(string src = "") {
		var functionHeaderRegex = "(function)[\s]*([\w]+)[\s]*\(([^)]+)\)[\s]*\{";
		var blockRegex = "(\{[^{}]+\})";
		var singleStatementRegex = "\)[\s]+?([^,;{][^;{]+;)";
		var callRegex = "(function[\s]*)?([\w\.]+)(?:[\s]+)?\(([^()]+)?\)(?:[\s]+?___block_([\d]+))?";
		var structLiteralRegex = "=[\s]*___block_([0-9]+)";
		var structLiteralMatch = 0;
		var structLiteralBlock = 0;
		var structLiteralBlockIndex = 0;
		var blocks = [];
		var blockPosition = 0;
		var blockIndex = 1;
		var targetBlockIndex = 0;
		var block = 0;
		var statementIndex = 0;
		var statement = 0;
		var statementHead = 0;
		var statementTail = 0;
		var perLoopStatement = 0;
		var calls = [];
		var callPosition = 0;
		var callIndex = 1;
		var call = 0;
		var declarations = {};
		var receiveMatch = 0;

		// remove comments and whitespace
		src = reReplace(
			reReplace(
				reReplace(
					src,
					"\/\/.+?\n",
					"",
					"ALL"),
				"[\s]+",
				" ",
				"ALL"),
			"\/\*.+?\*\/",
			"",
			"ALL");
		
		// TODO: Escape string contents (not entirely trivial)
		
		// wrap single statement blocks e.g. if (x) y = 1 becomes if (x) {y = 1}
		src = reReplace(src, singleStatementRegex, ") {\1}", "ALL");
		
		// re-write empty blocks to work around parsing issue
		src = replace(src, "{}", "{ }", "ALL");
		src = replace(src, "}}", "} }", "ALL");
		
		// factor out block hierarchy
		
		blockPosition = reFind(blockRegex, src);
		
		if (this.debug) writeOutput("<h2>Factor Out Blocks</h2>");
		
		while (blockPosition neq 0) {
			block = trim(listLast(listFirst(mid(src, blockPosition, 99999), "}"), "{"));
			blocks[blockIndex] = listToArray(block, ";");
			//writeLog("block #blockIndex# = '#block#'");
			src = "#left(src, find("{", src, blockPosition) - 1)# ___block_#blockIndex++#; #mid(src, find("}", src, blockPosition) + 1, 99999)#";
			blockPosition = reFind(blockRegex, src);
			
			if (this.debug) {
				writeOutput("<hr/><div width='600'><pre>#htmlCodeFormat(replace(src, ";", chr(10), "all"))#</pre></div>");
				writeDump(blocks);
			}
		}
		
		if (this.debug) writeOutput("<h2>Factor Out Calls</h2>");
				
		for (blockIndex = 1; blockIndex le arrayLen(blocks); blockIndex++) {
			for (statementIndex = 1; statementIndex le arrayLen(blocks[blockIndex]); statementIndex++) {
				
				statement = blocks[blockIndex][statementIndex];
					
				// rewrite for(;;) as while, because otherwise people will complain about not having "for"

				if (reFind("for([\s]+)?\(", blocks[blockIndex][statementIndex])) {
					statement = listLast(statement, "(");
					blocks[blockIndex][statementIndex] = statement;
					perLoopStatement = blocks[blockIndex][statementIndex + 2];
					targetBlockIndex = listLast(perLoopStatement, "_");
					blocks[blockIndex][statementIndex+1] = "while(#blocks[blockIndex][statementIndex+1]#) ___block_#targetBlockIndex#";
					arrayAppend(blocks[targetBlockIndex], left(perLoopStatement, reFind("\)([\s]+)?___block_", perLoopStatement) - 1));
					arrayDeleteAt(blocks[blockIndex], statementIndex + 2);
				}
				
				// rewrite struct literals as calls to helper _gt_struct_literal()
				structLiteralMatch = reFind(structLiteralRegex, statement, 1, true);
				
				if (structLiteralMatch.len[1] neq 0) {
					
					structLiteralBlockIndex = mid(statement, structLiteralMatch.pos[2], structLiteralMatch.pos[2]);
					structLiteralBlock = blocks[structLiteralBlockIndex][1];
					blocks[structLiteralBlockIndex] = "SKIP_STRUCT_LITERAL";
					
					statement = left(statement, structLiteralMatch.pos[1] - 1) &
						"= _gt_struct_literal(" &
						structLiteralBlock &
						")" &
						mid(statement, structLiteralMatch.pos[1] + structLiteralMatch.len[1], 999999);
				}
				
				
				// factor out calls
				
				callPosition = reFindNoCase(callRegex, statement, 1, true);
				
				while (callPosition.len[1] neq 0) {
					
					call = {};
					
					call.name = mid(statement, callPosition.pos[3], callPosition.len[3]);
					
					if (callPosition.len[2] neq 0) {
						call.isDeclaration = true;
						declarations[call.name] = call;
					} else {
						call.isDeclaration = false;
					}
					
					if (callPosition.pos[4] neq 0) {
						call.args = mid(statement, callPosition.pos[4], callPosition.len[4]);
					} else {
						call.args = "";
					}
						
					if (callPosition.pos[5] neq 0)
						call.block = mid(statement, callPosition.pos[5], callPosition.len[5]);
					
					arrayAppend(calls, call);
					
					if (callPosition.pos[1] eq 1)
						statementHead = "";
					else
						statementHead = left(statement, callPosition.pos[1] - 1);
						
					if (callPosition.pos[1] + callPosition.len[1] eq len(statement) + 1)
						statementTail = "";
					else
						statementTail = mid(statement, callPosition.pos[1] + callPosition.len[1], 99999);
					
					statement = "#statementHead# ___call_#callIndex++# #statementTail#";
					blocks[blockIndex][statementIndex] = statement;
					callPosition = reFindNoCase(callRegex, statement, 1, true);
					
				} // while callPosition
				
				if (this.debug) {
					writeOutput("<hr/><table><tr><td>");
					writeDump(blocks);
					writeOutput("</td><td>");
					writeDump(calls);
					writeOutput("</td></tr></table>");
				}
				
			} // for statementIndex
		} // for blockIndex
		
		return {src = src, blocks = blocks, calls = calls, declarations = declarations};
	}
	
	
	
	
	/**
	 * Based on parseComponent Results, re-write the component greener-thread style
	 *
	 * @param	info		parsed component information returned by parseComponent()
	 * @param	superclass	The name of the component we are rewriting, so that we can
	 *						extend it for type polymorphism
	 * @returns				The rewritten component, including symbols, closures and the _gt_step() function
	 */
	 
	private string function writeComponent(struct info, string superclass) {
		var caseLabelRegex = "^case(?:[\s]+)(.+?):(.*)";
		var defaultLabelRegex = "default(?:[\s]+)?:(.*)";
		var blockIndex = 0;
		var statement = 0;
		var statementIndex = 0;
		var statementCounter = 1;
		var blockOffsets = [];
		var statements = [];
		var symbols = [];
		var vars = {};
		var callIndex = 0;
		var call = 0;
		var callsToMakeIterator = 0;
		var nextCallToMakeIndex = 0;
		var nextCallToMake = 0;
		var skipStatements = 0;
		var declarations = [];
		var declarationName = 0;
		
		// Build up lists of statements, vars, closures etc for final assembly of component source code
		
		for (declarationName in info.declarations) {
			arrayAppend(declarations, '	private struct function _gt_args_#declarationName#(#info.declarations[declarationName].args#) {return arguments;}');
		}
		
		for (blockIndex = 1; blockIndex lt arrayLen(info.blocks); blockIndex++) {	// note: not including last block, which is actual component structure
			
			if (not isSimpleValue(info.blocks[blockIndex])) {
				
				blockOffsets[blockIndex] = statementCounter;
				arrayAppend(symbols, "			block_#blockIndex# = #statementCounter#");
				skipStatements = false;
				
				for (statementIndex = 1; statementIndex le arrayLen(info.blocks[blockIndex]); statementIndex++) {
					
					statement = trim(info.blocks[blockIndex][statementIndex]);
					
					// detect case labels
					caseMatch = reScrape(caseLabelRegex, statement);
					
					if (arrayLen(caseMatch) eq 1) {
						
						arrayAppend(symbols, "			block_#blockIndex#_case_#reReplace(caseMatch[1][2], "[^\w\d]", "", "ALL")# = #statementCounter#");
						statement = caseMatch[1][3];
						
					}
					
					caseMatch = reScrape(defaultLabelRegex, statement);
					
					if (arrayLen(caseMatch) eq 1) {
						
						arrayAppend(symbols, "			block_#blockIndex#_case_default = #statementCounter#");
						statement = caseMatch[1][2];
						
					}
					
					if (statement neq "" and not skipStatements) {
						
						callsToMakeIterator = orderedCallList(info.calls, statement).iterator();
						
						while (callsToMakeIterator.hasNext()) {
							
							nextCallToMakeIndex = callsToMakeIterator.next();
							nextCallToMake = info.calls[nextCallToMakeIndex];
							
							if (structKeyExists(info.declarations, nextCallToMake.name)) {
								
								arrayAppend(statements, 	'			case #statementCounter++#: _gt.incPc(); _gt.pushStackFrame(#nextCallToMakeIndex#, _gt.getSymbolLocation("#nextCallToMake.name#"), _gt_args_#nextCallToMake.name#(#nextCallToMake.args#)); break;');
								
							} else {
								
								// TODO: else, try/catch
								
								switch(nextCallToMake.name) {
									case "switch":
										arrayAppend(statements, '			case #statementCounter++#:');
										arrayAppend(statements, '				_gt.incPc();');
										arrayAppend(statements, '				_gt_case_symbol_location = _gt.getSymbolLocation("block_#nextCallToMake.block#_case_##reReplace(#nextCallToMake.args#, "[^\w\d]", "", "ALL")##");');
										arrayAppend(statements, '				_gt_default_symbol_location = _gt.getSymbolLocation("block_#nextCallToMake.block#_case_default");');
										arrayAppend(statements, '				if(_gt_case_symbol_location gt 0) {');
										arrayAppend(statements, '					 _gt.pushPc(_gt_case_symbol_location);');
										arrayAppend(statements, '				} else if (_gt_default_symbol_location gt 0) {');
										arrayAppend(statements, '					_gt.pushPc(_gt_default_symbol_location);');
										arrayAppend(statements, '				}');
										arrayAppend(statements, '				break;');
										break;
									case "if":
										arrayAppend(statements, '			case #statementCounter++#: _gt.incPc(); if (#renderCall(nextCallToMake.args)#) {_gt.pushPc(_gt.getSymbolLocation("block_#nextCallToMake.block#"));} break;');
										break;
									case "while":
										arrayAppend(statements, '			case #statementCounter++#: if (#renderCall(nextCallToMake.args)#) _gt.pushPc(_gt.getSymbolLocation("block_#nextCallToMake.block#")); else _gt.incPc(); break;');
										break;
									case "send":
										arrayAppend(statements, '			case #statementCounter++#: _gt.setReturnValue(#nextCallToMakeIndex#, _gt.send(#renderCall(nextCallToMake.args)#)); _gt.incPc(); break;');
										break;
									case "receive":										
										arrayAppend(statements, '			case #statementCounter++#: _gt.receive(#nextCallToMakeIndex#); break;');
										break;
									case "_gt_struct_literal":
										arrayAppend(statements, '			case #statementCounter++#: _gt.setReturnValue(#nextCallToMakeIndex#, _gt.structLiteral(#renderCall(nextCallToMake.args)#)); _gt.incPc(); break;');
										break;
									case "getTid":
										arrayAppend(statements, '			case #statementCounter++#: _gt.setReturnValue(#nextCallToMakeIndex#, _gt.getTid()); _gt.incPc(); break;');
										break;
									case "writeLog":
									case "writeDump":
										// These look like functions but are actually tags that don't like being treated like functions (we get weird CF error)
										// TODO: Other function-like tags
										arrayAppend(statements, '			case #statementCounter++#: #nextCallToMake.name#(#renderCall(nextCallToMake.args)#); _gt.incPc(); break;');
										break;
									default: 
										arrayAppend(statements, '			case #statementCounter++#: _gt.setReturnValue(#nextCallToMakeIndex#, #nextCallToMake.name#(#renderCall(nextCallToMake.args)#)); _gt.incPc(); break;');
								} //switch
							} // else
						}  // while callsToMake
						
						if (left(statement, 5) eq "break") {
							arrayAppend(statements, '			case #statementCounter++#: _gt.popPc(); break;');
						} else if (left(statement, 6) eq "return") {
							
							arrayAppend(statements, '			case #statementCounter++#: _gt.popStackFrame(#renderCall(replaceNoCase(statement, "return", "", "one"))#); break;');
							skipStatements = true; // no point doing remainder of block after a return
							
						} else if (left(trim(statement), 4) eq "var ") {
							
							// We have to var this variable at the front of gt_step
							vars["var #listGetAt(statement, 2, " 	=")# = 0"] = true;
							arrayAppend(statements, '			case #statementCounter++#: #renderCall(listRest(statement, " "))#; _gt.incPc(); break;');
							
						} else if (not left(trim(statement), 8) eq "___call_") {		// Skip ignored return values
						
							arrayAppend(statements, '			case #statementCounter++#: #renderCall(statement)#; _gt.incPc(); break;');
							
						} // else if	
					} // if statement neq ""
				} // for statementIndex
				
				if (not skipStatements)
					arrayAppend(statements, '			case #statementCounter++#: _gt.popPc(); break;'); // end of the block
				
			} // not isSimple block
		} // for block index
		
		for (callIndex = arrayLen(info.calls); callIndex gt 0; callIndex--) {
			
			call = info.calls[callIndex];
			
			if (call.isDeclaration) {
				arrayAppend(symbols, '			#call.name# = #blockOffsets[call.block]#');
			}
		}
		
		// Final assembly of component source code
		
		return arrayToList([
			'component extends="#superclass#" {',
			'	',
			'	public void function _gt_init(thread, context) {',
			'		',
			'		_gt = new GreenerThread(this);',
			'		_gt.setSymbolLocations(',
			arrayToList(symbols, ",#chr(13)#"),
			'		);',
			'	',
			'		if (not isNumeric(thread.stack[1].pc[1])) thread.stack[1].pc[1] = _gt.getSymbolLocation(thread.stack[1].pc[1]);',
			'		_gt.setContext(thread, context);',
			'	}',
			'	',
			arrayToList(declarations, chr(13)),
			'	',
			'	public function _gt_getSymbol(string symbol) {return _gt.getSymbolLocation(symbol);}',
			'	',
			'	public boolean function _gt_step() {',
			'		' & structKeyList(vars, ";") & ";",
			'	',
			'		structAppend(local, _gt.getFrameLocalVariables());',
			'	',
			'		switch(_gt.getPc()) {',
			'	',
			arrayToList(statements, chr(13)),
			'			default: return false;',
			'	',
			'		}',
			'		',
			'		_gt.saveLocalVariables(local);',
			'		',
			'		return _gt.threadHasStackFrames();',
			'	}',
			'}'
		], chr(13));
	}
	
	
	
	/**
	 * Replace all ___call_x instances with final code
	 *
	 * @param	s	string to substitute into
	 * @returns		string with substitutions
	 */
	 
	private string function renderCall(string s) {
		return trim(reReplace(s, "___call_([\d]+)", "_gt.getReturnValue(\1)", "ALL"));
	}
	
	
	
	/**
	 * List all the calls that need to be made in increasing order to prepare arguments for the specified fragment of code
	 *
	 * @param	calls		Array of known call details
	 * @param	fragment	The block or call arguments code fragment to look for a tree of calls in
	 * @returns				An ordered list of call indicies refered to from this code fragment
	 */
	 
	private Array function orderedCallList(Array calls, string fragment) {
		var callRegex = "___call_([\d]+)";
		var callMap = {};
		var fragmentsToDo = [fragment];
		var matches = 0;
		var iter = 0;
		var nextCallIndex = 0;
		var result = 0;
		
		while (not arrayIsEmpty(fragmentsToDo)) {
			
			iter = reScrape(callRegex, fragmentsToDo[1]).iterator();
			arrayDeleteAt(fragmentsToDo, 1);
			
			while (iter.hasNext()) {
				nextCallIndex = iter.next()[2];
				
				if (not structKeyExists(callMap, nextCallIndex)) {
					arrayAppend(fragmentsToDo, calls[nextCallIndex].args);
				}
				
				callMap[nextCallIndex] = true;

			}
		}
		result = listToArray(structKeyList(callMap));
		arraySort(result, "numeric", "asc");
		return result;
	}
	
	
	
	
	
	
	// Utility methods
	
	
	
	/**
	 * Return array of re matches and their subexpressions
	 *
	 * @param regex		Regular expression
	 * @param source	string to search in
	 * @returns			A two dimensional array [matchIndex][subExpressionIndex] = "matched sub expression"
	 */
	 
	private Array function reScrape(string regex, string source) {
		var startIndex = 1;
		var resultIndex = 1;
		var result = 0;
		var maxIndex = len(source);
		var matches = arrayNew(1);
		var terms = 0;

		while (startIndex lt maxIndex) {
	
			result = reFind(regex, source, startIndex, true);
			
			if (result.pos[1] neq 0) {
				terms = arrayNew(1);
			
				for (resultIndex = 1; resultIndex le arrayLen(result.pos); resultIndex = resultIndex + 1) {
					if (result.len[resultIndex] neq 0) {
						arrayAppend(terms, mid(source, result.pos[resultIndex], result.len[resultIndex]));
						startIndex = max(startIndex, result.pos[resultIndex] + result.len[resultIndex]);
					}
				}
			
				arrayAppend(matches, terms);
			
			} else {
				break;
			}
		}
		
		return matches;
	}
	
	
	
	/**
	 * Default filter function for receive accepts all messages
	 */
	 
	private boolean function defaultFilter() {
		return true;
	}
	 
}