[haproxy]
%{ for index, group in hostnames ~}
${ hostnames[index] }.${region}.${rootdomain}
%{ endfor ~}