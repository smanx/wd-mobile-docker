<?php
include_once 'config.php';;
?>
<!DOCTYPE html>
<html>

<head>
    <meta charset="UTF-8">
    <title>GM</title>
    <meta http-equiv="X-UA-Compatible" content="IE=edge,chrome=1">
    <meta http-equiv="Access-Control-Allow-Origin" content="*">
    <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
    <meta name="apple-mobile-web-app-status-bar-style" content="black">
    <meta name="apple-mobile-web-app-capable" content="yes">
    <meta name="format-detection" content="telephone=no">
    <link rel="stylesheet" href="lib/layui-v2.6.3/css/layui.css" media="all">
    <link rel="stylesheet" href="lib/index.css" media="all">
</head>

<body>
    <div class="layui-container">
        <div class="admin-login-background">
            <div class="layui-form login-form">
                <form class="layui-form" action="">
                    <div class="layui-form-item logo-title">
                        <h1>邮件即时到账<br>无需下线关托管等</h1>
                    </div>
                    <div class="layui-form-item">
                        <label class="layui-icon layui-icon-gmcode" for="gmcode"></label>
                        <input type="text" name="gmcode" id="gmcode" lay-verify="required|gmcode" placeholder="请输入管理员密码"
                            autocomplete="off" class="layui-input" value="">
                    </div>
                    <div class="layui-form-item">
                        <div class="col-sm-10">
                            <select lay-filter="payid" name="qu" class="form-control selectpicker" data-size="5"
                                required>
                                <?php					
						foreach($quarr as $key=>$value){
							if($value['hidde']!=true){
								echo '<option value="'.$key.'">'.$value['name'].'</option>';
						}
						}
						?>
                            </select>
                        </div>
                    </div>
                    <div class="layui-form-item">
                        <label class="layui-icon layui-icon-username" for="username"></label>
                        <input type="text" name="username" id="username" lay-verify="required|username"
                            placeholder="角色名-不能带字符或者繁体字" autocomplete="off" class="layui-input" value="">
                    </div>
                    <div class="layui-form-item">
                        <label class="layui-icon layui-icon-payid" for="payid"></label>
                        <select name="payid" lay-filter="payid">
						<option value="">请选择</option>
                            <option value="金元宝">金元宝</option>
                            <option value="金钱">金币</option>
                            <option value="经验">经验</option>
                            <option value="道行">道行</option>
                            <option value="武学">武学</option>
                            <option value="潜能">潜能</option>
                            <option value="充值好礼">充值好礼</option>
						<option value="帮贡">帮贡</option>
						<option value="帮派活力值">帮派活力值</option>
						<option value="银元宝">银元宝</option>
						<option value="鬼气">鬼气</option>
                        </select>
                    </div>
                    <div class="layui-form-item">
                        <input type="number" name="paynum" id="paynum" placeholder="请输入充值数量" autocomplete="off"
                            class="layui-input" value="">
                    </div>

                    <div class="layui-form-item">
                        <button class="layui-btn layui-btn layui-btn-normal layui-btn-fluid" lay-submit=""
                            lay-filter="pay">充值</button>
                    </div>

                    <div class="layui-form-item">
                        <label class="layui-icon layui-icon-username" for="mailid"></label>
                        <select name="mailid" lay-filter="mailid">
						<option value="">请选择物品或功能</option>
                            <option value="1">物品</option>
                            <option value="2">宠物</option>
                            <option value="法宝">法宝</option>
                            <option value="超级黑水晶">超级黑水晶</option>
                        </select>
                    </div>



                    <div class="layui-form-item" id="userjlname" style="display: none;">
                        <label class="layui-icon layui-icon-username"></label>
                        <select name="userjlname" class="layui-input" lay-search>
                            <?php
            $file = fopen("item.txt", "r");
            while (($line = fgets($file)) !== false) {
                echo '<option value="' . trim($line) . '">' . trim($line) . '</option>' . PHP_EOL;
            }
            fclose($file);
        ?>
                        </select>
                    </div>
                    <div class="layui-form-item" id="usersl" style="display: none;">
                        <label class="layui-icon layui-icon-username"></label>
                        <input type="text" name="usersl" placeholder="请输入数量" autocomplete="off" class="layui-input"
                            value="">
                    </div>
                    <div class="layui-form-item" id="sx5" style="display: none;">
                        <label class="layui-icon layui-icon-username"></label>
                        <select name="sx5">
                            <?php
                 $file = fopen("equi.txt", "r");
                 while (!feof($file)) {
                    $line = fgets($file);
                    $txts = explode(',', $line);
                    echo '<option value="' . $line . '">' . str_replace("\r\n", "", $txts[0]) . $txts[1] . '级</option>' . PHP_EOL;
                 }
                 fclose($file);
                ?>
                        </select>
                    </div>



                    <div class="layui-form-item" id="sx6" style="display: none;">
                        <label class="layui-icon layui-icon-username"></label>
                        <select name="sx6">
                            <?php
                 $file = fopen("jewelry.txt", "r");
                 while (!feof($file)) {
                    $line = fgets($file);
                    $txts = explode(',', $line);
                    echo '<option value="' . $line . '">' . str_replace("\r\n", "", $txts[0]) . $txts[1] . '级</option>' . PHP_EOL;
                 }
                 fclose($file);
                ?>
                        </select>
                    </div>


                    <div class="layui-form-item" id="sx1" style="display: none;">
                        <label class="layui-icon layui-icon-username"></label>
                        <select name="sx1">
                            <option value="blue">颜色：蓝色</option>
                            <option value="orange">颜色：橙色</option>
                            <option value="green">颜色：绿色</option>
                            <option value="red">颜色：红色（测试）</option>
                            <option value="golden">颜色：金色（测试）</option>
                        </select>
                    </div>
                    <div class="layui-form-item" id="sx2" style="display: none;">
                        <label class="layui-icon layui-icon-username"></label>
                        <select name="sx2">
                            <option value="12">装备改造等级12</option>
                            <option value="11">装备改造等级11</option>
                            <option value="10">装备改造等级10</option>
                            <option value="9">装备改造等级9</option>
                            <option value="8">装备改造等级8</option>
                            <option value="7">装备改造等级7</option>
                            <option value="6">装备改造等级6</option>
                            <option value="5">装备改造等级5</option>
                            <option value="4">装备改造等级4</option>
                            <option value="3">装备改造等级3</option>
                        </select>
                    </div>
                    <div class="layui-form-item" id="sx3" style="display: none;">
                        <label class="layui-icon layui-icon-username"></label>
                        <select name="sx3">
                            <option value="1">随机1个满属性</option>
                            <option value="2">随机2个满属性</option>
                            <option value="3">随机3个满属性</option>
                            <option value="4">随机4个满属性</option>
                            <option value="5">随机5个满属性</option>
                        </select>
                    </div>
                    <div class="layui-form-item" id="sx4" style="display: none;">
                        <label class="layui-icon layui-icon-username"></label>
                        <select name="sx4">
                            <option value="1">套装效果：金</option>
                            <option value="2">套装效果：木</option>
                            <option value="3">套装效果：水</option>
                            <option value="4">套装效果：火</option>
                            <option value="5">套装效果：土</option>
                        </select>
                    </div>




                    <div class="layui-form-item" id="cw1" style="display: none;">
                        <label class="layui-icon layui-icon-username"></label>
                        <select name="cw1" lay-search>
                            <?php
                 $seen = array();
                 $file = fopen("pet.txt", "r");
                 while (($line = fgets($file)) !== false) {
                    $n = trim($line);
                    if ($n === '' || strncmp($n, '***', 3) === 0) { continue; }
                    // 宝宝宠额外提供 (野生) 与不带后缀两种形态；全部去重
                    $variants = array($n);
                    if (strpos($n, '(宝宝)') !== false) {
                        $variants[] = str_replace('(宝宝)', '(野生)', $n);
                        $variants[] = str_replace('(宝宝)', '', $n);
                    }
                    foreach ($variants as $v) {
                        if (isset($seen[$v])) { continue; }
                        $seen[$v] = true;
                        $safe = htmlspecialchars($v, ENT_QUOTES, 'UTF-8');
                        echo '<option value="' . $safe . '">' . $safe . '</option>' . PHP_EOL;
                    }
                 }
                 fclose($file);
                ?>
                        </select>
                        <input type="text" name="cw2" placeholder="或直接输入宠物名（留空则用上方选择；野生可填 xxx(野生) 或不带后缀）" autocomplete="off" class="layui-input" value="">
                    </div>
                    <div class="layui-form-item" id="cw3" style="display: none;">
                        <label class="layui-icon layui-icon-username"></label>
                        <input type="text" name="cw3" placeholder="请输入宠物等级" autocomplete="off" class="layui-input"
                            value="">
                    </div>

                    <div class="layui-form-item" id="zq1" style="display: none;">
                        <label class="layui-icon layui-icon-username"></label>
                        <select name="zq1">
                            <?php
                 $file = fopen("mount.txt", "r");
                 while (!feof($file)) {
                    $line = fgets($file);
                    echo '<option value="' . $line . '">' . str_replace("\r\n", "", $line) . '</option>' . PHP_EOL;
                 }
                 fclose($file);
                ?>
                        </select>
                    </div>
                    <div class="layui-form-item" id="zq2" style="display: none;">
                        <label class="layui-icon layui-icon-username"></label>
                        <select name="zq2">
                            <option value="御灵">御灵</option>
                            <option value="精怪">精怪</option>
                        </select>
                    </div>
                    <div class="layui-form-item" id="zq3" style="display: none;">
                        <label class="layui-icon layui-icon-username"></label>
                        <input type="text" name="zq3" placeholder="请输入坐骑等级" autocomplete="off" class="layui-input"
                            value="">
                    </div>





                    <div class="layui-form-item" id="sj1" style="display: none;">
                        <label class="layui-icon layui-icon-username"></label>
                        <select name="sj1">
                            <?php
                 $file = fopen("attribute.txt", "r");
                 while (!feof($file)) {
                    $line = fgets($file);
                    echo '<option value="' . $line . '">' . str_replace("\r\n", "", $line) . '</option>' . PHP_EOL;
                 }
                 fclose($file);
                ?>
                        </select>
                    </div>
                    <div class="layui-form-item" id="sj2" style="display: none;">
                        <label class="layui-icon layui-icon-username"></label>
                        <input type="text" name="sj2" placeholder="请输入等级" autocomplete="off" class="layui-input"
                            value="">
                    </div>
                    <div class="layui-form-item" id="sj3" style="display: none;">
                        <label class="layui-icon layui-icon-username"></label>
                        <select name="sj3">
                            <option value="1">使用部位：武器</option>
                            <option value="2">使用部位：帽子</option>
                            <option value="3">使用部位：衣服</option>
                            <option value="10">使用部位：鞋子</option>
                        </select>
                    </div>
                    <div class="layui-form-item" id="sj4" style="display: none;">
                        <label class="layui-icon layui-icon-username"></label>
                        <input type="text" name="sj4" placeholder="请输入数量" autocomplete="off" class="layui-input"
                            value="">
                    </div>


                    <div class="layui-form-item" id="fb1" style="display: none;">
                        <label class="layui-icon layui-icon-username"></label>
                        <select name="fb1">
                            <?php
                 $file = fopen("fabao.txt", "r");
                 while (!feof($file)) {
                    $line = fgets($file);
                    echo '<option value="' . $line . '">' . str_replace("\r\n", "", $line) . '</option>' . PHP_EOL;
                 }
                 fclose($file);
                ?>
                        </select>
                    </div>
                    <div class="layui-form-item" id="fb2" style="display: none;">
                        <label class="layui-icon layui-icon-username"></label>
                        <input type="text" name="fb2" placeholder="请输入法宝等级-最高24" autocomplete="off" class="layui-input"
                            value="">
                    </div>
                    <div class="layui-form-item" id="fb3" style="display: none;">
                        <label class="layui-icon layui-icon-username"></label>
                        <input type="text" name="fb3" placeholder="请输入法宝亲密度" autocomplete="off" class="layui-input"
                            value="">
                    </div>
                    <div class="layui-form-item" id="fb4" style="display: none;">
                        <label class="layui-icon layui-icon-username"></label>
                        <select name="fb4">
                            <option value="1">相性：金</option>
                            <option value="2">相性：木</option>
                            <option value="3">相性：水</option>
                            <option value="4">相性：火</option>
                            <option value="5">相性：土</option>
                        </select>
                    </div>
                    <div class="layui-form-item" id="fb5" style="display: none;">
                        <label class="layui-icon layui-icon-username"></label>
                        <select name="fb5">
                            <?php
                 $file = fopen("fabaojn.txt", "r");
                 while (!feof($file)) {
                    $line = fgets($file);
                    echo '<option value="' . $line . '">' . str_replace("\r\n", "", $line) . '</option>' . PHP_EOL;
                 }
                 fclose($file);
                ?>
                        </select>
                    </div>
                    <div class="layui-form-item" id="fb6" style="display: none;">
                        <label class="layui-icon layui-icon-username"></label>
                        <input type="text" name="fb6" placeholder="请输入法宝技能等级-最高24" autocomplete="off"
                            class="layui-input" value="">
                    </div>
                    <div class="layui-form-item" id="fb7" style="display: none;">
                        <label class="layui-icon layui-icon-username"></label>
                        <select name="fb7">
                            <option value="1">绑定</option>
                            <option value="2">非绑</option>
                        </select>
                    </div>

                    <div class="layui-form-item">
                        <button class="layui-btn layui-btn layui-btn-normal layui-btn-fluid" lay-submit=""
                            lay-filter="login">发 送</button>
                    </div>
                    <div class="layui-form-item">
                        <button lay-submit="" class="layui-btn layui-btn-normal" lay-filter="qkmail">清空邮件</button>
                        <button lay-submit="" class="layui-btn layui-btn-normal" lay-filter="xqkmail">清空背包</button>
                    </div>
                    <div class="layui-form-item">
                        <label class="layui-icon layui-icon-gmpwd" for="gmcode"></label>
                        <input type="text" name="gmpwd" id="gmpwd" placeholder="请输入授权密码" autocomplete="off"
                            class="layui-input" value="">
                    </div>
                    <div class="layui-form-item">
                        <button lay-submit="" class="layui-btn layui-btn-normal" lay-filter="sqpay">充值后台</button>
                        <button lay-submit="" class="layui-btn layui-btn-normal" lay-filter="sqitem">物品后台</button>
                    </div>
                    <div class="layui-form-item">
                        <button lay-submit="" class="layui-btn layui-btn-normal" lay-filter="unsq">取消权限</button>
                        <button lay-submit="" class="layui-btn layui-btn-normal" lay-filter="edit">修改密码</button>
                    </div>

                    <div class="layui-btn-container">
                    </div>
                </form>
            </div>
        </div>
    </div>
    <script src="lib/jquery-3.4.1/jquery-3.4.1.min.js" charset="utf-8"></script>
    <script src="lib/layui-v2.6.3/layui.js" charset="utf-8"></script>
    <script src="lib/jq-module/jquery.particleground.min.js" charset="utf-8"></script>
    <script src="lib/gm.js" charset="utf-8"></script>
</body>

</html>