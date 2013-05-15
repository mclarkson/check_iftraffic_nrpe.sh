<?php
#
#
# Define some colors

$red        = '#FF0000';
$magenta    = '#FF00FF';
$navy       = '#000080';
$green      = '#008000';
$yellow     = '#FFFF00';
$orangered  = '#FF4500';
$darkred    = '#8B0000';
$blue       = '#0000FF';
$darkblue   = '#000099';
$darkorange = '#FF8C00';


$line[1]     = $navy;
$line[2]     = $orangered;

$counter = 1;

$servicedesc = str_replace("_", " ", $servicedesc);

# Main logic

foreach ($DS as $i)
        {
        $maxcounter = $i;
        }

for ($loopcounter = 1; $loopcounter < $maxcounter; $loopcounter++)
    {
    $interface = $NAME[$loopcounter];
    #$interface = ereg_replace("_.*$", "", $interface);
    $interface = preg_replace("/^.*-/", "", $interface);
    $ds_name[$counter] = $interface;
    
    $opt[$counter] = " --vertical-label \"Traffic\" -b 1000  --title \"Interface Traffic for $hostname / $servicedesc\" ";
    
    $def[$counter] = "DEF:inbound=$RRDFILE[$loopcounter]:$DS[$loopcounter]:AVERAGE " ;

    $loopcounter++;
    $def[$counter] .= "DEF:outbound=$RRDFILE[$loopcounter]:$DS[$loopcounter]:AVERAGE " ;
    $def[$counter] .= "LINE1:inbound$line[1]:\"in  \" " ;
    
    $def[$counter] .= "GPRINT:inbound:LAST:\"%7.2lf %SB/s last\" " ;
    $def[$counter] .= "GPRINT:inbound:AVERAGE:\"%7.2lf %SB/s avg\" " ;
    $def[$counter] .= "GPRINT:inbound:MAX:\"%7.2lf %SB/s max\\n\" " ;
    
    $def[$counter] .= "LINE1:outbound$line[2]:\"out \" " ;
    
    $def[$counter] .= "GPRINT:outbound:LAST:\"%7.2lf %SB/s last\" " ;
    $def[$counter] .= "GPRINT:outbound:AVERAGE:\"%7.2lf %SB/s avg\" " ;
    $def[$counter] .= "GPRINT:outbound:MAX:\"%7.2lf %SB/s max\\n\" ";
    
    $counter++;
    }

?>
