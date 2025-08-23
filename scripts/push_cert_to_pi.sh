

## we need a script that will accept a paramater like:

scripts/push_cert_to_pi.sh cert1 cert2 pi1
scripts/push_cert_to_pi.sh cert3 cert4 pi2

#and use the default pi if not provided on the cli
scripts/push_cert_to_pi.sh cert5 cert6

#Once copied in - hup the nginx via it's service
pi -??? pi1 "sudo systemctl restart nginx"