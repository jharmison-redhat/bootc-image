#!/bin/bash

if ! aws iam get-role --role-name vmimport >/dev/null 2>&1; then
    aws iam create-role --role-name vmimport --assume-role-policy-document file://hack/trust-policy.json
fi

envsubst '$S3_BUCKET' <hack/role-policy.json.tpl >tmp/role-policy.json

aws iam put-role-policy --role-name vmimport --policy-name vmimport-$$S3_BUCKET --policy-document file://tmp/role-policy.json
