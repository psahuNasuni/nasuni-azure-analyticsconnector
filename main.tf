resource "null_resource" "provision_nac" {
  provisioner "local-exec" {
     command = "sh prov-nac.sh"
  }
  
}
