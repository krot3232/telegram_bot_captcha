<?php
while (FALSE !== ($line = fgets(STDIN)))
{
	$result=get_captcha();
	$line=json_decode(trim($line),true);
	$line['code']=$result['code'];
	$line['file']=$result['file'];
	echo json_encode($line);
}
function get_captcha(){
	$length = rand(5,6);
	$chars = 'ABCDEFGHJKLMNPQRSTVWXYZ123456789';
	$code = '';
	for ($i = 0; $i < $length; $i++) {
		$code .= $chars[rand(0, strlen($chars) - 1)];
	}
	$width = 150;
	$height = 40;
	$image = imagecreatetruecolor($width, $height);
	$bgColor = imagecolorallocate($image, 255, 255, 255);
	imagefill($image, 0, 0, $bgColor);
	for ($i = 0, $l=rand(5,20); $i < $l; $i++) {
		$noiseColor = imagecolorallocate($image, rand(150,255), rand(150,255), rand(150,255));
		imageline($image, rand(0,$width), rand(0,$height), rand(0,$width), rand(0,$height), $noiseColor);
	}
	for ($i = 0, $l=rand(100,200); $i < $l; $i++) {
		$dotColor = imagecolorallocate($image, rand(100,200), rand(100,200), rand(100,200));
		imagesetpixel($image, rand(0,$width), rand(0,$height), $dotColor);
	}
	$x = 10;
	$y = 12;
	for ($i = 0; $i < strlen($code); $i++) {
		$textColor = imagecolorallocate($image, rand(0,150), rand(0,150), rand(0,150));
		imagestring($image, rand(3,5), $x, $y, $code[$i], $textColor);
		$x += 25;
	}
	$temp = tempnam(sys_get_temp_dir(), "CAP");
	imagejpeg($image,$temp);
	imagedestroy($image);
	return array('code'=>$code,'file'=>$temp);
}