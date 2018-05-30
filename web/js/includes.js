$(function() {
	$('#includenavbar').load('/parts/navbar.html', function() { 
		feather.replace(); 
		$("#"+$("body").data("navbaractive")).addClass("active");
	});
	$('#includeheader').load('/parts/header.html', function() { feather.replace(); });
});