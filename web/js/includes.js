$(function() {
	$('#includenavbar').load('/parts/navbar.html', function() { 
		$("#"+$("body").data("navbaractive")).addClass("active");
	});
	$('#includeheader').load('/parts/header.html', function() {});
});