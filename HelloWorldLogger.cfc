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