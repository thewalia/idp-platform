#!/bin/bash

echo "🔍 IDP Security Assessment Report"
echo "================================="
echo ""

echo "📊 Current Kyverno Policies Status:"
echo "-----------------------------------"
kubectl get cpol,pol -A --no-headers | wc -l | xargs echo "Total policies installed:"
echo ""

echo "🚨 Policy Violations (Current):"
echo "------------------------------"
kubectl get policyreports -A --no-headers 2>/dev/null | grep -v "pass" | head -10
kubectl get clusterpolicyreports --no-headers 2>/dev/null | grep -v "pass" | head -10
echo ""

echo "🔐 Service Account Token Audit:"
echo "------------------------------"
echo "Pods with automountServiceAccountToken != false:"
kubectl get pods -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{.spec.automountServiceAccountToken}{"\n"}{end}' | grep -E "(true|^[^\t]*\t[^\t]*\t$)" | head -10
echo ""

echo "📏 Resource Limits Audit:"
echo "------------------------"
echo "Containers without resource limits:"
kubectl get pods -A -o json | jq -r '.items[] | select(.spec.containers[]? | has("resources") | not or (.spec.containers[]?.resources | has("limits") | not)) | "\(.metadata.namespace)\t\(.metadata.name)"' | head -10
echo ""

echo "🛡️ Security Context Audit:"
echo "-------------------------"
echo "Containers running as root (no runAsNonRoot):"
kubectl get pods -A -o json | jq -r '.items[] | select(.spec.securityContext.runAsNonRoot != true and (.spec.containers[]?.securityContext.runAsNonRoot != true)) | "\(.metadata.namespace)\t\(.metadata.name)"' | head -10
echo ""

echo "🖼️ Image Pull Policy Audit:"
echo "--------------------------"
echo "Containers with imagePullPolicy != Always:"
kubectl get pods -A -o json | jq -r '.items[] | .metadata as $meta | .spec.containers[] | select(.imagePullPolicy != "Always") | "\($meta.namespace)\t\($meta.name)\t\(.image)\t\(.imagePullPolicy // "IfNotPresent")"' | head -10
echo ""

echo "📁 HostPath Volume Usage:"
echo "------------------------"
echo "Pods using hostPath volumes:"
kubectl get pods -A -o json | jq -r '.items[] | select(.spec.volumes[]?.hostPath) | "\(.metadata.namespace)\t\(.metadata.name)\t\(.spec.volumes[] | select(.hostPath) | .name)"' | head -10
echo ""

echo "🔑 Privileged Containers:"
echo "------------------------"
echo "Containers running in privileged mode:"
kubectl get pods -A -o json | jq -r '.items[] | .metadata as $meta | .spec.containers[] | select(.securityContext.privileged == true) | "\($meta.namespace)\t\($meta.name)\t\(.name)"'
echo ""

echo "📋 Summary:"
echo "----------"
echo "Run this assessment after each policy implementation to ensure no regressions."
echo "Focus areas: ServiceAccount tokens, Resource limits, Security contexts, Image policies"
echo ""
echo "Next Steps:"
echo "1. Review violations above"
echo "2. Fix critical issues in manifests"
echo "3. Implement policies gradually"
echo "4. Re-run assessment after each change"
