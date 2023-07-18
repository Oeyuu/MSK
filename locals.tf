locals {
  acc_id       = "143805577160"
  company_name = "teclify"
  prefix       = "${local.company_name}-sandbox-${local.acc_id}"
  app          = "msk"
  full_prefix  = "${local.prefix}-${local.app}"

}
