<cfif thisTag.ExecutionMode eq "start">

	<cfparam name="request.stage" default="">

	<cfset match = REFind("(.+?)([0-9]+)\.cfm", cgi.SCRIPT_NAME, 1, true)>
	<cfset slidePath = mid(cgi.SCRIPT_NAME, match.pos[2], match.len[2])>
    <cfset slideNum = mid(cgi.SCRIPT_NAME, match.pos[3], match.len[3])>

	<html>
	<head>
	<style>
		body {
			font-family:Arial, Helvetica, sans-serif;
		}
		p {margin: 0px 0px 5px 25px; 	padding: 0px; color: #006699; background: inherit; }
		hr { border: 0; height: 1px; color: #eee; background-color: #eee; }
		a { 	color: #0F5B7F; background: inherit;  text-decoration:none; }
		a:hover { 	background: inherit;	text-decoration: underline; }
		h1 { padding:0px; margin:20px; color: #0F5B7F; background: inherit;font: bold 1.7em Arial, Sans-Serif; letter-spacing: -1px; }
		h1 a {color: #0F5BFF; background: inherit;}
		h2 { background-color: inherit; 	color:#0F5B7F; font-size:140%; font-weight:bold; margin: 10px 0 10px 0; padding:0; }
		h2 a { color: #0F5B7F; }
		h2 a:hover { 	color: #0F5BAF; text-decoration: none;}

		ul {
			margin: 5px 20px 20px 45px;
			padding : 5 5 5 5px;
			list-style-position: outside;
			list-style-type: circle;
			font-size: 14px;
		}
		ol {
			margin: 5px 0 20px 15px;
			line-height: normal;
			list-style-position: outside;
			font-size: 14px;
		}

		li {
			color: #006699;
			margin: 0 0 0px 0;
			padding: 5 5 5 5px;
			font-size: 14px;
			line-height: normal;
			list-style-position: outside;
		}
		li a { color: #546078;  text-decoration:underline;}
		li a:hover { color: #3366FF; }
		.faint {color: #999999; margin: 25px; font-size:70%;}
		.faint a {color: #999999;}
		#prevNavigation {
			position:absolute;
			left:600px;
			top:10px;
			width:35px;
			height:35px;
			z-index:1;
		}
		#nextNavigation {
			position:absolute;
			left:650px;
			top:10px;
			width:35px;
			height:35px;
			z-index:2;
		}
	}
	</style>
	</head><body>
	<cfoutput>
	<div id="prevNavigation" onClick="location.href='#slidePath##right("0" & (slideNum - 1), 2)#.cfm'"><img src="images/prevButton.png" alt="previous button" width="35" height="34" /></div>
	<div id="nextNavigation" onClick="location.href='#slidePath##right("0" & (slideNum + 1), 2)#.cfm'"><img src="images/nextButton.png" alt="previous button" width="35" height="34" /></div>
	<h1>#attributes.title#</h1>
	<hr>
	</cfoutput>

<cfelse>
	<br><br>
	<cfoutput><span class="faint">&copy; 2012 RocketBoots Pty Limited</span></cfoutput>
	</body>
	</html>

</cfif>