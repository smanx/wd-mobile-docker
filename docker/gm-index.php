<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
 <meta name="applicable-device" content="mobile">
    <meta http-equiv="Content-Type" content="text/html; charset=UTF-8">
    <meta content="width=device-width, initial-scale=1,maximum-scale=1.0,user-scalable=no" name="viewport"/>
    <!-- 游戏全屏 -->
    <meta content="true" name="full-screen"/>
    <meta content="true" name="x5-fullscreen"/>
    <meta content="true" name="360-fullscreen"/>
    <!--iphone qq -->
    <meta name="x5-orientation" content="portrait">
    <meta name="x5-fullscreen" content="true">
    <meta name="x5-page-mode" content="app">
<meta name="viewport" content="width=device-width, initial-scale=1, user-scalable=no" />
<link rel="shortcut icon" href="static/images/favicon.ico" type="image/x-icon">
<meta name="description" content="">
<meta name="keywords" content="">
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
<meta name="apple-mobile-web-app-capable" content="yes" />
<title>玩家后台</title>
<script src="static/js/jquery.js"></script>
    <script src="static/js/jquery.lazyload.js"></script>
<script src="static/js/layer.js"></script>
<script src="static/js/cookie.js"></script>
 
<script src="static/js/sdk_core.js"></script>
<link rel="stylesheet" href="static/css/mainnew.css"/>
<link rel="stylesheet" href="static/css/main.css"/>
<link rel="stylesheet" href="static/css/animations.css">
</head>
<body>
<div class="wrapper">
<div class="main">
<div class="nav">
<ul id="tab">
<li class="tab"><a href="javascript:;">玩家后台</a></li>
<li class="tab"><a href="javascript:;">成品装备</a></li>
<li class="tab"><a href="javascript:;">自助授权</a></li>

</ul>
</div>
<div class="gamelist tab_cont">
<iframe height="800px" width="100%" src="index2.php">
        </iframe>
</div>
<div class="gamelist tab_cont" style="display:none;"><!--默认 -->
<iframe height="800px" width="100%" src="./cp/">
        </iframe>
</div>

<div class="gamelist tab_cont" style="display:none;"><!--默认 -->
<iframe height="800px" width="100%" src="./pay/">
        </iframe>
</div>


</div>


</div>


<script src="static/js/jquery.slides.min.js"></script>
<script type="text/javascript">

 $('#slides').slidesjs({
 	width : 640,
 	height : 250,
 	pagination: {active: false,effect: "slide"}, 
 	play: {active: false, auto: true, interval: 3000, swap: false},
 	navigation: {active: false}
 });
 $('#gd').slidesjs({
 	width : 640,
 	pagination: {active: false,effect: "slide"}, 
 	play: {active: false, auto: true, interval: 3000, swap: false},
 	navigation: {active: false}

 });
$(document).ready(function(){
    $("#tab li").click(function(){
        var liindex = $("#tab li").index(this);
        $("#tab").find("li").removeClass("active");
        $(this).addClass("active");
        $(".tab_cont").eq(liindex).show().siblings(".tab_cont").hide();
    });
    
    
    
    
});


            /* 修复：移除门户模板残留的 Swiper 初始化（页面无 .content 结构、未引入 swiper.min.js，原会抛 ReferenceError） */

</script>
</body>
</html>