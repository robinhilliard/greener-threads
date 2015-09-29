component {

	function init(pid, count) {
		countdown(pid, count);
	}
	
	function countdown(pid, count) {
		send(pid,count);
		if (count gt 0) {
			countdown(pid, count--);
		}
	}
	
}