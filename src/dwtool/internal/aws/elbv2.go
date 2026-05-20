package aws

import (
	"context"
	"fmt"
	"strings"

	"github.com/aws/aws-sdk-go-v2/aws"
	elbv2 "github.com/aws/aws-sdk-go-v2/service/elasticloadbalancingv2"
	elbv2types "github.com/aws/aws-sdk-go-v2/service/elasticloadbalancingv2/types"

	"dreamwidth.org/dwtool/internal/config"
	"dreamwidth.org/dwtool/internal/model"
)

// FetchTrafficRule discovers the ALB listener rule for a given web service
// and returns the current target group weights.
func (c *Client) FetchTrafficRule(ctx context.Context, serviceKey string) (model.TrafficRule, error) {
	// 1. Find ALB by name
	lbs, err := c.elbv2.DescribeLoadBalancers(ctx, &elbv2.DescribeLoadBalancersInput{
		Names: []string{config.ALBName},
	})
	if err != nil {
		return model.TrafficRule{}, fmt.Errorf("describing ALB: %w", err)
	}
	if len(lbs.LoadBalancers) == 0 {
		return model.TrafficRule{}, fmt.Errorf("ALB %q not found", config.ALBName)
	}
	albARN := aws.ToString(lbs.LoadBalancers[0].LoadBalancerArn)

	// 2. Find HTTPS listener (port 443)
	listeners, err := c.elbv2.DescribeListeners(ctx, &elbv2.DescribeListenersInput{
		LoadBalancerArn: aws.String(albARN),
	})
	if err != nil {
		return model.TrafficRule{}, fmt.Errorf("describing listeners: %w", err)
	}
	var listenerARN string
	for _, l := range listeners.Listeners {
		if l.Port != nil && *l.Port == 443 {
			listenerARN = aws.ToString(l.ListenerArn)
			break
		}
	}
	if listenerARN == "" {
		return model.TrafficRule{}, fmt.Errorf("no HTTPS listener found on %s", config.ALBName)
	}

	// 3. Get all rules for this listener
	rules, err := c.elbv2.DescribeRules(ctx, &elbv2.DescribeRulesInput{
		ListenerArn: aws.String(listenerARN),
	})
	if err != nil {
		return model.TrafficRule{}, fmt.Errorf("describing rules: %w", err)
	}

	// 4. Find the matching rule
	tgPrefix := serviceKey + "-tg"
	for _, rule := range rules.Rules {
		isDefault := aws.ToBool(rule.IsDefault)
		targets := extractTargets(rule.Actions)

		// Match by TG name: look for a TG whose name is exactly serviceKey + "-tg"
		for _, t := range targets {
			if t.Name == tgPrefix {
				label := fmt.Sprintf("Rule %s", aws.ToString(rule.Priority))
				if isDefault {
					label = "Default"
				}
				return model.TrafficRule{
					RuleARN:     aws.ToString(rule.RuleArn),
					ListenerARN: listenerARN,
					IsDefault:   isDefault,
					ServiceKey:  serviceKey,
					Label:       label,
					Targets:     targets,
				}, nil
			}
		}
	}

	return model.TrafficRule{}, fmt.Errorf("no ALB rule found for %s", serviceKey)
}

// UpdateTrafficWeights applies new target group weights to an ALB rule.
// For the listener's default action, it uses ModifyListener; for other
// rules, it uses ModifyRule.
func (c *Client) UpdateTrafficWeights(ctx context.Context, rule model.TrafficRule) error {
	var tgTuples []elbv2types.TargetGroupTuple
	for _, t := range rule.Targets {
		w := int32(t.Weight)
		tgTuples = append(tgTuples, elbv2types.TargetGroupTuple{
			TargetGroupArn: aws.String(t.ARN),
			Weight:         &w,
		})
	}

	action := elbv2types.Action{
		Type: elbv2types.ActionTypeEnumForward,
		ForwardConfig: &elbv2types.ForwardActionConfig{
			TargetGroups: tgTuples,
		},
	}

	if rule.IsDefault {
		_, err := c.elbv2.ModifyListener(ctx, &elbv2.ModifyListenerInput{
			ListenerArn:    aws.String(rule.ListenerARN),
			DefaultActions: []elbv2types.Action{action},
		})
		if err != nil {
			return fmt.Errorf("modifying listener default action: %w", err)
		}
	} else {
		_, err := c.elbv2.ModifyRule(ctx, &elbv2.ModifyRuleInput{
			RuleArn: aws.String(rule.RuleARN),
			Actions: []elbv2types.Action{action},
		})
		if err != nil {
			return fmt.Errorf("modifying rule: %w", err)
		}
	}

	return nil
}

// extractTargets pulls target group weights from a rule's forward action.
func extractTargets(actions []elbv2types.Action) []model.TargetGroupWeight {
	for _, action := range actions {
		if action.Type == elbv2types.ActionTypeEnumForward && action.ForwardConfig != nil {
			var targets []model.TargetGroupWeight
			for _, tg := range action.ForwardConfig.TargetGroups {
				name := tgNameFromARN(aws.ToString(tg.TargetGroupArn))
				weight := 0
				if tg.Weight != nil {
					weight = int(*tg.Weight)
				}
				targets = append(targets, model.TargetGroupWeight{
					ARN:    aws.ToString(tg.TargetGroupArn),
					Name:   name,
					Weight: weight,
				})
			}
			return targets
		}
	}
	return nil
}

// tgNameFromARN extracts the target group name from its ARN.
// ARN format: arn:aws:elasticloadbalancing:region:account:targetgroup/name/hex
func tgNameFromARN(arn string) string {
	parts := strings.Split(arn, "/")
	if len(parts) >= 2 {
		return parts[1]
	}
	return arn
}
