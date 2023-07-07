provider "aws" {
  region = "eu-central-1"
}

resource "aws_kms_key" "msk" {
  description = "msk"

}

resource "aws_cloudwatch_log_group" "msk" {
  name = "msk_broker_logs"
}

resource "aws_msk_cluster" "mskcluster" {
  cluster_name           = var.cluster_name
  kafka_version          = "3.2.0"
  number_of_broker_nodes = 3

  broker_node_group_info {
    instance_type   = "kafka.t3.small"
    client_subnets  = aws_subnet.public.*.id
    security_groups = [aws_security_group.sg.id]
    storage_info {
      ebs_storage_info {
        volume_size = 10
      }
    }
    connectivity_info {
      public_access {
        type = "SERVICE_PROVIDED_EIPS"
      }
    }
  }

  encryption_info {
    encryption_at_rest_kms_key_arn = aws_kms_key.msk.arn
  }

  open_monitoring {
    prometheus {
      jmx_exporter {
        enabled_in_broker = true
      }
      node_exporter {
        enabled_in_broker = true
      }
    }
  }

  logging_info {
    broker_logs {
      cloudwatch_logs {
        enabled   = true
        log_group = aws_cloudwatch_log_group.msk.name
      }

    }
  }

  client_authentication {
    sasl {
      iam   = true
      scram = true
    }
  }

  configuration_info {
    arn      = data.aws_msk_configuration.msk.arn
    revision = data.aws_msk_configuration.msk.latest_revision
  }
}

resource "aws_msk_configuration" "msk" {
  kafka_versions = ["3.2.0"]
  name           = "msk-config"
  #hier acl false setzen wenn root acls vorhanden
  server_properties = <<PROPERTIES
  allow.everyone.if.no.acl.found=false
  auto.create.topics.enable=false
  default.replication.factor=3
  min.insync.replicas=2
  num.io.threads=8
  num.network.threads=5
  num.partitions=1
  num.replica.fetchers=2
  replica.lag.time.max.ms=30000
  socket.receive.buffer.bytes=102400
  socket.request.max.bytes=104857600
  socket.send.buffer.bytes=102400
  unclean.leader.election.enable=true
  zookeeper.session.timeout.ms=18000
  PROPERTIES
}

data "aws_msk_configuration" "msk" {
  name       = "msk-config"
  depends_on = [aws_msk_configuration.msk]
}


resource "random_password" "super_user" {
  length           = 20
  special          = true
  override_special = "_%@"
}

resource "aws_secretsmanager_secret" "super_user" {
  name                    = "AmazonMSK_super_user"
  kms_key_id              = aws_kms_key.msk.arn
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "super_user" {
  secret_id     = aws_secretsmanager_secret.super_user.id
  secret_string = jsonencode({ "username" : "super_user", "password" : random_password.super_user.result })
}

resource "aws_secretsmanager_secret_policy" "super_user" {
  secret_arn = aws_secretsmanager_secret.super_user.arn
  policy     = data.aws_iam_policy_document.super_user.json
}

data "aws_iam_policy_document" "super_user" {
  statement {
    effect = "Allow"
    principals {
      identifiers = ["kafka.amazonaws.com"]
      type        = "Service"
    }
    actions   = ["secretsmanager:getSecretValue"]
    resources = [aws_secretsmanager_secret.super_user.arn]
  }
}

resource "null_resource" "aws_msk_scram_secret_association" {
  depends_on = [aws_secretsmanager_secret.super_user]

  provisioner "local-exec" {
    when    = create
    command = "aws kafka batch-associate-scram-secret --cluster-arn ${aws_msk_cluster.mskcluster.arn} --secret-arn-list ${aws_secretsmanager_secret.super_user.arn}"
  }
}

resource "null_resource" "aws_msk_scram_secret_disassociation" {
  triggers = {
    cluster-arn     = aws_msk_cluster.mskcluster.arn
    secret-arn-list = aws_secretsmanager_secret.super_user.arn
  }

  provisioner "local-exec" {
    when    = destroy
    command = "aws kafka batch-disassociate-scram-secret --cluster-arn ${self.triggers.cluster-arn} --secret-arn-list ${self.triggers.secret-arn-list}"
  }
}






