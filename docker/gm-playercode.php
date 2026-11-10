<?php
include 'config.php';

$pwd = trim($_POST['gmcode']);
$quid = trim($_POST['qu']);
$qu = $quarr[$quid];
$dbip   = $qu['dbip'];
$dbus   = $qu['dbus'];
$dbps   = $qu['dbps'];
$dbdb   = $qu['dbdb'];
$conn = new mysqli($dbip, $dbus, $dbps, $dbdb);	
if ($conn->connect_error) {send("数据库链接失败");}	
$user = $_POST['username'];	
$conn->set_charset("latin1");
$sql = "SELECT * FROM gid_info where name='".iconv('UTF-8','GB2312',$user)."'";
$result_1 = $conn->query($sql);
$row_1 = mysqli_fetch_assoc($result_1);	
$uid = $row_1['gid'];
$currentTimestamp = time();
if($uid == ''){send("角色不存在！");}
if ($pwd == '') {send("密钥错误");}


                $vipfile = 'q95736310-' . $quid . '.json';
                $fp = fopen($vipfile, "a+");
                if (filesize($vipfile) > 1) {
                    $str = fread($fp, filesize($vipfile));
                    fclose($fp);
                    $vipjson = json_decode($str, true);
                    if ($vipjson == null) {
                        $vipjson = array();
                    }
                } else {
                    $vipjson = array();
                }
                if (!$vipjson[$user]) {
					send("你没有后台权限。");
                } elseif ($vipjson[$user]['pwd'] != $pwd) {
					send("用户设置密码不匹配");
                }
                if ($vipjson[$user]['quid'] != $quid) {
					send("设置用户与当前选择大区不匹配");
                }
                $viplevel = intval($vipjson[$user]['level']);

                 if ($_POST['type']) {
                    $type = trim($_POST['type']);
                    switch ($type) {
                        case 'pay':
						    $payid  = trim($_POST['payid']);
							$paynum = trim($_POST['paynum']);
						    $attachment = '"#I'.$payid.'|'.$payid.'#r'.$paynum.'#I"';
                            $misc = '"#O感谢大哥赞助！请查收您的奖励"';
                            sendgm($uid,$attachment,$misc,$conn);							
							
                        break;
                        case 'mail':
						    if ($viplevel < 2) {
								send("VIP权限不足");
                            }
						    $mailid  = trim($_POST['mailid']);
						    $item = $_POST['c5'];$num = $_POST['c6'];
						    $cw1 = $_POST['cw1'];$cw2 = $_POST['cw2'];
						    $cw3 = $_POST['cw3'];$zq1 = $_POST['zq1'];
						    $zq2 = $_POST['zq2'];$zq3 = $_POST['zq3'];
						    $zdy = $_POST['zdy'];$sx1 = $_POST['sx1'];
						    $sx2 = $_POST['sx2'];$sx3 = $_POST['sx3'];
						    $sx4 = $_POST['sx4'];$sx5 = $_POST['sx5'];
						    $sx6 = $_POST['sx6'];$sj1 = $_POST['sj1'];
						    $sj2 = $_POST['sj2'];$sj3 = $_POST['sj3'];
						    $sj4 = $_POST['sj4'];$fb1 = $_POST['fb1'];
						    $fb2 = $_POST['fb2'];$fb3 = $_POST['fb3'];
						    $fb4 = $_POST['fb4'];$fb5 = $_POST['fb5'];
						    $fb6 = $_POST['fb6'];$fb7 = $_POST['fb7'];
							if($mailid == 1){
							    $attachment = '"#I物品|'.$item.'#r'.$num.'#I"';
							    $misc = '"#O感谢大哥赞助！请查收您的奖励"';
							}    
							if($mailid == 2){
							    $petname = (isset($cw2) && trim($cw2) !== '') ? trim($cw2) : trim($cw1);
							    $attachment = '"#I宠物|' . $petname . '$' . $cw3 . '$3#I"';
							    $misc = '"#O感谢大哥赞助！请查收您的奖励"';
							}
							if($mailid == '超级黑水晶'){
							    $txts = explode(',', trim($sj1));
							    $sjsx1 = $txts[0];
							    $sjsx2 = $txts[1];
							    $attachment = '"#I超级黑水晶|超级黑水晶·' . $sjsx1 . '$' . $sj2 . '$' . $sj3 . '$' . $sjsx2 . '$max#r' . $sj4 .'#I"';
							    $misc = '"#O感谢大哥赞助！请查收您的奖励"'; 
							}
							if($mailid == '法宝'){
							    if($fb7 == 1){
							       $fbbb = '%bind'; 
							    }
							    $attachment = '"#I法宝|'. trim($fb1) . '$'.$fb2.'$' . $fb4 . '$friendliness=' . $fb3 . '$spskill=' . $fb5 . '$spskillLV=' . $fb6 . $fbbb . '#I"';
							   $misc = '"#O感谢大哥赞助！请查收您的奖励"';
							}
							sendgm($uid,$attachment,$misc,$conn);
                        break;
                        case 'qkmail':
                            qkmail($uid,$conn);							
							
                        break;
                        case 'xqkmail':
                            xqkmail($uid,$conn);							
							
                        break;						                       
                        default:
                            exit('系统异常，请重试!');
                        break;
                    }
                } else {
                    exit('请求类型不存在！');
                }	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	