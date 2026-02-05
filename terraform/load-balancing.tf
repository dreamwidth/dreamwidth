# load-balancing.tf - Application Load Balancers, listeners, target groups

# =============================================================================
# ALBs
# =============================================================================

# Production ALB (web traffic)
resource "aws_lb" "prod" {
  name               = "dw-prod"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = local.subnets

  enable_deletion_protection = true
  enable_http2               = true

  tags = {
    sla = "production"
  }
}

# Proxy ALB
resource "aws_lb" "proxy" {
  name               = "dw-proxy"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = local.subnets

  enable_deletion_protection = true
  enable_http2               = true

  tags = {
    sla = "production"
  }
}

# =============================================================================
# Target Groups - Web Services
# =============================================================================

resource "aws_lb_target_group" "web_stable" {
  name        = "web-stable-tg"
  port        = 6081
  protocol    = "HTTP"
  vpc_id      = local.vpc_id
  target_type = "ip"

  load_balancing_algorithm_type = "least_outstanding_requests"

  health_check {
    enabled             = true
    healthy_threshold   = 3
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 29
    path                = "/"
    matcher             = "200"
  }

  stickiness {
    type            = "lb_cookie"
    enabled         = false
    cookie_duration = 86400
  }

}

resource "aws_lb_target_group" "web_stable_2" {
  name        = "web-stable-2-tg"
  port        = 6081
  protocol    = "HTTP"
  vpc_id      = local.vpc_id
  target_type = "ip"

  load_balancing_algorithm_type = "least_outstanding_requests"

  health_check {
    enabled             = true
    healthy_threshold   = 3
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 29
    path                = "/"
    matcher             = "200"
  }

  stickiness {
    type            = "lb_cookie"
    enabled         = false
    cookie_duration = 86400
  }

}

resource "aws_lb_target_group" "web_canary" {
  name        = "web-canary-tg"
  port        = 6081
  protocol    = "HTTP"
  vpc_id      = local.vpc_id
  target_type = "ip"

  load_balancing_algorithm_type = "least_outstanding_requests"

  health_check {
    enabled             = true
    healthy_threshold   = 3
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 29
    path                = "/"
    matcher             = "200"
  }

  stickiness {
    type            = "lb_cookie"
    enabled         = false
    cookie_duration = 86400
  }

}

resource "aws_lb_target_group" "web_canary_2" {
  name        = "web-canary-2-tg"
  port        = 6081
  protocol    = "HTTP"
  vpc_id      = local.vpc_id
  target_type = "ip"

  load_balancing_algorithm_type = "least_outstanding_requests"

  health_check {
    enabled             = true
    healthy_threshold   = 3
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 29
    path                = "/"
    matcher             = "200"
  }

  stickiness {
    type            = "lb_cookie"
    enabled         = false
    cookie_duration = 86400
  }

}

resource "aws_lb_target_group" "web_shop" {
  name        = "web-shop-tg"
  port        = 6081
  protocol    = "HTTP"
  vpc_id      = local.vpc_id
  target_type = "ip"

  load_balancing_algorithm_type = "least_outstanding_requests"

  health_check {
    enabled             = true
    healthy_threshold   = 3
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 29
    path                = "/"
    matcher             = "200"
  }

  stickiness {
    type            = "lb_cookie"
    enabled         = false
    cookie_duration = 86400
  }

}

resource "aws_lb_target_group" "web_shop_2" {
  name        = "web-shop-2-tg"
  port        = 6081
  protocol    = "HTTP"
  vpc_id      = local.vpc_id
  target_type = "ip"

  load_balancing_algorithm_type = "least_outstanding_requests"

  health_check {
    enabled             = true
    healthy_threshold   = 3
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 29
    path                = "/"
    matcher             = "200"
  }

  stickiness {
    type            = "lb_cookie"
    enabled         = false
    cookie_duration = 86400
  }

}

resource "aws_lb_target_group" "web_unauthenticated" {
  name        = "web-unauthenticated-tg"
  port        = 6081
  protocol    = "HTTP"
  vpc_id      = local.vpc_id
  target_type = "ip"

  load_balancing_algorithm_type = "least_outstanding_requests"

  health_check {
    enabled             = true
    healthy_threshold   = 3
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 29
    path                = "/"
    matcher             = "200"
  }

  stickiness {
    type            = "lb_cookie"
    enabled         = false
    cookie_duration = 86400
  }

}

resource "aws_lb_target_group" "web_unauthenticated_2" {
  name        = "web-unauthenticated-2-tg"
  port        = 6081
  protocol    = "HTTP"
  vpc_id      = local.vpc_id
  target_type = "ip"

  load_balancing_algorithm_type = "least_outstanding_requests"

  health_check {
    enabled             = true
    healthy_threshold   = 3
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 29
    path                = "/"
    matcher             = "200"
  }

  stickiness {
    type            = "lb_cookie"
    enabled         = false
    cookie_duration = 86400
  }

}

# =============================================================================
# Target Groups - Proxy
# =============================================================================

resource "aws_lb_target_group" "proxy" {
  name        = "proxy-stable-tg"
  port        = 6250
  protocol    = "HTTP"
  vpc_id      = local.vpc_id
  target_type = "ip"

  load_balancing_algorithm_type = "least_outstanding_requests"

  health_check {
    enabled             = true
    healthy_threshold   = 3
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 5
    path                = "/robots.txt"
    matcher             = "200"
  }

  stickiness {
    type            = "lb_cookie"
    enabled         = false
    cookie_duration = 86400
  }

}

# =============================================================================
# Target Groups - EC2 Instances (legacy infrastructure)
# =============================================================================

resource "aws_lb_target_group" "dw_maint" {
  name        = "dw-maint"
  port        = 82
  protocol    = "HTTP"
  vpc_id      = local.vpc_id
  target_type = "instance"

  health_check {
    path = "/health-check"
  }

  lifecycle {
    ignore_changes = [health_check]
  }
}

resource "aws_lb_target_group" "dw_stats" {
  name        = "dw-stats"
  port        = 8082
  protocol    = "HTTP"
  vpc_id      = local.vpc_id
  target_type = "instance"

  health_check {
    path = "/"
  }

  lifecycle {
    ignore_changes = [health_check]
  }
}

resource "aws_lb_target_group" "ghi_assist" {
  name        = "ghi-assist"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = local.vpc_id
  target_type = "instance"

  health_check {
    path = "/health-check"
  }

  lifecycle {
    ignore_changes = [health_check]
  }
}

resource "aws_lb_target_group" "dw_embedded" {
  name        = "dw-embedded"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = local.vpc_id
  target_type = "instance"

  health_check {
    path = "/"
  }

  lifecycle {
    ignore_changes = [health_check]
  }
}

# =============================================================================
# Listeners (keeping original names from import)
# =============================================================================

# Prod ALB - HTTPS (port 443)
resource "aws_lb_listener" "r_51c219f8069621b6_443" {
  load_balancer_arn = aws_lb.prod.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = "arn:aws:acm:us-east-1:194396987458:certificate/23c066c3-f228-4144-b29f-b0aa98ef8945"

  default_action {
    type = "forward"
    forward {
      target_group {
        arn    = aws_lb_target_group.web_unauthenticated.arn
        weight = 100
      }
      target_group {
        arn    = aws_lb_target_group.web_unauthenticated_2.arn
        weight = 0
      }
      stickiness {
        enabled  = false
        duration = 3600
      }
    }
  }

  lifecycle {
    ignore_changes = [default_action]
  }
}

# Prod ALB - HTTP (port 80) - redirects to HTTPS
resource "aws_lb_listener" "r_51c219f8069621b6_80" {
  load_balancer_arn = aws_lb.prod.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }

  lifecycle {
    ignore_changes = [default_action]
  }
}

# Proxy ALB - HTTPS (port 443)
resource "aws_lb_listener" "r_35f0700031428f07_443" {
  load_balancer_arn = aws_lb.proxy.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = "arn:aws:acm:us-east-1:194396987458:certificate/23c066c3-f228-4144-b29f-b0aa98ef8945"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.proxy.arn
  }

  lifecycle {
    ignore_changes = [default_action]
  }
}

# Proxy ALB - HTTP (port 80)
resource "aws_lb_listener" "r_35f0700031428f07_80" {
  load_balancer_arn = aws_lb.proxy.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.proxy.arn
  }

  lifecycle {
    ignore_changes = [default_action]
  }
}

# =============================================================================
# Listener Rules (keeping original names from import)
# =============================================================================

# Rule 3: /interface/github -> ghi-assist
resource "aws_lb_listener_rule" "r_51c219f8069621b6_443_rule_3" {
  listener_arn = aws_lb_listener.r_51c219f8069621b6_443.arn
  priority     = 3

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ghi_assist.arn
  }

  condition {
    path_pattern {
      values = ["/interface/github"]
    }
  }

  lifecycle {
    ignore_changes = [action, condition]
  }
}

# Rule 4: maintenance paths -> dw-maint
resource "aws_lb_listener_rule" "r_51c219f8069621b6_443_rule_4" {
  listener_arn = aws_lb_listener.r_51c219f8069621b6_443.arn
  priority     = 4

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.dw_maint.arn
  }

  condition {
    path_pattern {
      values = ["/admin/*"]
    }
  }

  lifecycle {
    ignore_changes = [action, condition]
  }
}

# Rule 5: stats -> dw-stats
resource "aws_lb_listener_rule" "r_51c219f8069621b6_443_rule_5" {
  listener_arn = aws_lb_listener.r_51c219f8069621b6_443.arn
  priority     = 5

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.dw_stats.arn
  }

  condition {
    path_pattern {
      values = ["/stats/*"]
    }
  }

  lifecycle {
    ignore_changes = [action, condition]
  }
}

# Rule 45: shop traffic
resource "aws_lb_listener_rule" "r_51c219f8069621b6_443_rule_45" {
  listener_arn = aws_lb_listener.r_51c219f8069621b6_443.arn
  priority     = 45

  action {
    type = "forward"
    forward {
      target_group {
        arn    = aws_lb_target_group.web_shop.arn
        weight = 100
      }
      target_group {
        arn    = aws_lb_target_group.web_shop_2.arn
        weight = 100
      }
      target_group {
        arn    = aws_lb_target_group.dw_maint.arn
        weight = 0
      }
      stickiness {
        enabled  = false
        duration = 3600
      }
    }
  }

  condition {
    host_header {
      values = ["shop.dreamwidth.org"]
    }
  }

  tags = {
    Name = "Shop Traffic"
  }
}

# Rule 50: canary traffic
resource "aws_lb_listener_rule" "r_51c219f8069621b6_443_rule_50" {
  listener_arn = aws_lb_listener.r_51c219f8069621b6_443.arn
  priority     = 50

  action {
    type = "forward"
    forward {
      target_group {
        arn    = aws_lb_target_group.web_canary.arn
        weight = 100
      }
      target_group {
        arn    = aws_lb_target_group.web_canary_2.arn
        weight = 100
      }
      target_group {
        arn    = aws_lb_target_group.dw_maint.arn
        weight = 0
      }
      stickiness {
        enabled  = false
        duration = 3600
      }
    }
  }

  condition {
    http_header {
      http_header_name = "Cookie"
      values           = ["*dwcanary=1*"]
    }
  }

  tags = {
    Name = "Canary Traffic"
  }
}

# Rule 55: stable traffic (default web)
resource "aws_lb_listener_rule" "r_51c219f8069621b6_443_rule_55" {
  listener_arn = aws_lb_listener.r_51c219f8069621b6_443.arn
  priority     = 55

  action {
    type = "forward"
    forward {
      target_group {
        arn    = aws_lb_target_group.web_stable.arn
        weight = 100
      }
      target_group {
        arn    = aws_lb_target_group.web_stable_2.arn
        weight = 0
      }
      target_group {
        arn    = aws_lb_target_group.dw_maint.arn
        weight = 0
      }
      stickiness {
        enabled  = false
        duration = 1
      }
    }
  }

  condition {
    host_header {
      values = ["www.dreamwidth.org"]
    }
  }

  tags = {
    Name = "Traffic With ljuniq Cookie"
  }

  lifecycle {
    ignore_changes = [action, condition]
  }
}

# HTTP listener rules (port 80)
resource "aws_lb_listener_rule" "r_51c219f8069621b6_80_rule_1" {
  listener_arn = aws_lb_listener.r_51c219f8069621b6_80.arn
  priority     = 1

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.dw_maint.arn
  }

  condition {
    path_pattern {
      values = ["/.well-known/*"]
    }
  }

  lifecycle {
    ignore_changes = [action, condition]
  }
}

resource "aws_lb_listener_rule" "r_51c219f8069621b6_80_rule_2" {
  listener_arn = aws_lb_listener.r_51c219f8069621b6_80.arn
  priority     = 2

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.dw_maint.arn
  }

  condition {
    path_pattern {
      values = ["/health-check"]
    }
  }

  lifecycle {
    ignore_changes = [action, condition]
  }
}
