#!/usr/bin/env python3
"""Verify the pinned bodyless bucket-configuration DELETE family."""

from __future__ import annotations

import copy
import csv
import re
import sys
import tomllib
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CORPUS = ROOT / "tests" / "corpora" / "delete-bucket-configurations"
MODEL = ROOT / "src" / "flyology-object_storage-s3-model.adb"
LOW_SPEC = ROOT / "src" / "flyology-object_storage-client-low_level.ads"
LOW_BODY = ROOT / "src" / "flyology-object_storage-client-low_level.adb"
HIGH_SPEC = ROOT / "src" / "flyology-object_storage-client-buckets.ads"
HIGH_BODY = ROOT / "src" / "flyology-object_storage-client-buckets.adb"
MODEL_SPEC = ROOT / "src" / "flyology-object_storage-s3-model.ads"
TESTING = (
    ROOT / "tests" / "src" /
    "flyology-object_storage-client-buckets-testing.adb"
)
SOCKET = ROOT / "tests" / "src" / "s3_http_socket_corpus.adb"
REGISTRY = ROOT / "coverage" / "s3-operations.toml"
QUALIFICATION = ROOT / "docs" / "qualification" / (
    "delete-bucket-configurations.md"
)
BUCKET_POLICY_QUALIFICATION = (
    ROOT / "docs" / "qualification" / "bucket-policy.md"
)
PUBLIC_ACCESS_BLOCK_QUALIFICATION = (
    ROOT / "docs" / "qualification" / "public-access-block.md"
)
LOCK = ROOT / "coverage" / "corpora.lock.toml"
EXPECTED_REVISION = "36c34f15391da01cd717c73c0fffa747c9889768"
EXPECTED_SHA256 = "429763d64912af5edae4c7a0f20a8ac3e6fecf734cde5fc465016bc8badcdef9"
DELETE_ENCRYPTION_CERTAINTY = (
    "only a complete validated 204 response with an exactly empty body "
    "reports Bucket_Encryption_Mutation_Completed; an exact recognized "
    "non-mutating rejection or definite non-admission reports "
    "Bucket_Encryption_Mutation_Definitely_Not_Applied; pre-admission "
    "cancellation reports "
    "Bucket_Encryption_Mutation_Cancelled_Before_Admission; possible or "
    "incomplete admission, retryable responses, and malformed or oversized "
    "responses report Bucket_Encryption_Mutation_Outcome_Unknown; no "
    "automatic replay"
)
DELETE_ENCRYPTION_RECONCILIATION = (
    "caller-selected Get_Encryption may observe the current "
    "default-encryption configuration before a retry, including SSE-S3 "
    "reset state, but does not prove that the lost deletion caused the "
    "observed state or upgrade mutation certainty; no automatic replay"
)
DELETE_ENCRYPTION_LANE = [
    [
        "uv", "run", "--python", "3.13", "--",
        "tools/verify-delete-bucket-configurations-preparation.py",
    ],
    ["@tests", "alr", "-n", "build"],
    ["@tests", "./bin/s3_delete_bucket_configurations_corpus"],
    ["@tests", "./bin/s3_http_socket_corpus"],
    ["./tools/verify-coverage.sh"],
    [
        "./tools/build-api-docs.sh",
        "/private/tmp/fos-delete-bucket-encryption-gnatdoc",
    ],
    ["./tools/ci/check-repository.sh", "{model}"],
    ["git", "diff", "--check"],
]
DELETE_LIFECYCLE_CERTAINTY = (
    "only a complete validated 204 response with an exactly empty body "
    "reports Bucket_Lifecycle_Mutation_Completed; an exact recognized "
    "non-mutating rejection or definite non-admission reports "
    "Bucket_Lifecycle_Mutation_Definitely_Not_Applied; pre-admission "
    "cancellation reports "
    "Bucket_Lifecycle_Mutation_Cancelled_Before_Admission; possible or "
    "incomplete admission, retryable responses, and malformed or "
    "oversized responses report Bucket_Lifecycle_Mutation_Outcome_Unknown; no "
    "automatic replay"
)
DELETE_LIFECYCLE_RECONCILIATION = (
    "caller-selected Get_Lifecycle_Configuration may observe the current "
    "lifecycle configuration or exact NoSuchLifecycleConfiguration before a "
    "retry, but does not prove that the lost deletion caused the "
    "observed absence or upgrade mutation certainty; no automatic replay"
)
DELETE_LIFECYCLE_LANE = [
    [
        "uv", "run", "--python", "3.13", "--",
        "tools/verify-delete-bucket-configurations-preparation.py",
    ],
    ["@tests", "alr", "-n", "build"],
    ["@tests", "./bin/s3_delete_bucket_configurations_corpus"],
    ["@tests", "./bin/s3_http_socket_corpus"],
    ["./tools/verify-coverage.sh"],
    [
        "./tools/build-api-docs.sh",
        "/private/tmp/fos-delete-bucket-lifecycle-gnatdoc",
    ],
    ["./tools/ci/check-repository.sh", "{model}"],
    ["git", "diff", "--check"],
]
DELETE_REPLICATION_CERTAINTY = (
    "only a complete validated 204 response with an exactly empty body "
    "reports Bucket_Replication_Mutation_Completed; an exact recognized "
    "non-mutating rejection or definite non-admission reports "
    "Bucket_Replication_Mutation_Definitely_Not_Applied; pre-admission "
    "cancellation reports "
    "Bucket_Replication_Mutation_Cancelled_Before_Admission; possible or "
    "incomplete admission, retryable responses, and malformed or oversized "
    "responses report Bucket_Replication_Mutation_Outcome_Unknown; no "
    "automatic replay"
)
DELETE_REPLICATION_RECONCILIATION = (
    "caller-selected Get_Replication_Configuration may observe the current "
    "replication configuration or exact "
    "ReplicationConfigurationNotFoundError before a retry, but does not prove "
    "that the lost deletion caused the observed absence or upgrade mutation "
    "certainty; no automatic replay"
)
DELETE_REPLICATION_LANE = [
    [
        "uv", "run", "--python", "3.13", "--",
        "tools/verify-delete-bucket-configurations-preparation.py",
    ],
    ["@tests", "alr", "-n", "build"],
    ["@tests", "./bin/s3_delete_bucket_configurations_corpus"],
    ["@tests", "./bin/s3_http_socket_corpus"],
    ["./tools/verify-coverage.sh"],
    [
        "./tools/build-api-docs.sh",
        "/private/tmp/fos-delete-bucket-replication-gnatdoc",
    ],
    ["./tools/ci/check-repository.sh", "{model}"],
    ["git", "diff", "--check"],
]
DELETE_WEBSITE_CERTAINTY = (
    "only a complete validated 204 response with an exactly empty body "
    "reports Bucket_Website_Mutation_Completed; an exact recognized "
    "non-mutating rejection or definite non-admission reports "
    "Bucket_Website_Mutation_Definitely_Not_Applied; pre-admission "
    "cancellation reports "
    "Bucket_Website_Mutation_Cancelled_Before_Admission; possible or "
    "incomplete admission, retryable responses, and malformed or oversized "
    "responses report Bucket_Website_Mutation_Outcome_Unknown; no automatic "
    "replay"
)
DELETE_WEBSITE_RECONCILIATION = (
    "caller-selected Get_Website may observe the current website "
    "configuration or exact NoSuchWebsiteConfiguration before a retry, but "
    "does not prove that the lost deletion caused the observed absence or "
    "upgrade mutation certainty; no automatic replay"
)
DELETE_WEBSITE_LANE = [
    [
        "uv", "run", "--python", "3.13", "--",
        "tools/verify-delete-bucket-configurations-preparation.py",
    ],
    ["@tests", "alr", "-n", "build"],
    ["@tests", "./bin/s3_delete_bucket_configurations_corpus"],
    ["@tests", "./bin/s3_http_socket_corpus"],
    ["./tools/verify-coverage.sh"],
    [
        "./tools/build-api-docs.sh",
        "/private/tmp/fos-delete-bucket-website-gnatdoc",
    ],
    ["./tools/ci/check-repository.sh", "{model}"],
    ["git", "diff", "--check"],
]
DELETE_ANALYTICS_CERTAINTY = (
    "only a complete validated 204 response with an exactly empty body "
    "reports Bucket_Analytics_Configuration_Mutation_Completed; an exact "
    "recognized non-mutating rejection or definite non-admission reports "
    "Bucket_Analytics_Configuration_Mutation_Definitely_Not_Applied; "
    "pre-admission cancellation reports "
    "Bucket_Analytics_Configuration_Mutation_Cancelled_Before_Admission; "
    "possible or incomplete admission, retryable responses, and malformed "
    "or oversized responses report "
    "Bucket_Analytics_Configuration_Mutation_Outcome_Unknown; no automatic "
    "replay"
)
DELETE_ANALYTICS_RECONCILIATION = (
    "caller-selected Get_Analytics_Configuration for the same identifier may "
    "observe the current configuration or exact NoSuchConfiguration before "
    "a retry, but does not prove that the lost deletion caused the observed "
    "absence or upgrade mutation certainty; no automatic replay"
)
DELETE_ANALYTICS_LANE = [
    [
        "uv", "run", "--python", "3.13", "--",
        "tools/verify-delete-bucket-configurations-preparation.py",
    ],
    ["@tests", "alr", "-n", "build"],
    ["@tests", "./bin/s3_delete_bucket_configurations_corpus"],
    ["@tests", "./bin/s3_http_socket_corpus"],
    ["./tools/verify-coverage.sh"],
    [
        "./tools/build-api-docs.sh",
        "/private/tmp/fos-delete-bucket-analytics-gnatdoc",
    ],
    ["./tools/ci/check-repository.sh", "{model}"],
    ["git", "diff", "--check"],
]
DELETE_INTELLIGENT_TIERING_CERTAINTY = (
    "only a complete validated 204 response with an exactly empty body "
    "reports Intelligent_Tiering_Mutation_Completed; an exact recognized "
    "non-mutating rejection or definite non-admission reports "
    "Intelligent_Tiering_Mutation_Definitely_Not_Applied; pre-admission "
    "cancellation reports Intelligent_Tiering_Mutation_Cancelled_Before_"
    "Admission; possible or incomplete admission, retryable responses, and "
    "malformed or oversized responses report "
    "Intelligent_Tiering_Mutation_Outcome_Unknown; no automatic replay"
)
DELETE_INTELLIGENT_TIERING_RECONCILIATION = (
    "caller-selected Get_Intelligent_Tiering_Configuration for the same "
    "identifier may observe the current configuration or exact "
    "NoSuchConfiguration before a retry, but does not prove that the lost "
    "deletion caused the observed absence or upgrade mutation certainty; no "
    "automatic replay"
)
DELETE_INTELLIGENT_TIERING_LANE = [
    [
        "uv", "run", "--python", "3.13", "--",
        "tools/verify-delete-bucket-configurations-preparation.py",
    ],
    ["@tests", "alr", "-n", "build"],
    ["@tests", "./bin/s3_delete_bucket_configurations_corpus"],
    ["@tests", "./bin/s3_http_socket_corpus"],
    ["./tools/verify-coverage.sh"],
    [
        "./tools/build-api-docs.sh",
        "/private/tmp/fos-delete-bucket-intelligent-tiering-gnatdoc",
    ],
    ["./tools/ci/check-repository.sh", "{model}"],
    ["git", "diff", "--check"],
]
DELETE_INVENTORY_CERTAINTY = (
    "only a complete validated 204 response with an exactly empty body "
    "reports Bucket_Inventory_Configuration_Mutation_Completed; an exact "
    "recognized non-mutating rejection or definite non-admission reports "
    "Bucket_Inventory_Configuration_Mutation_Definitely_Not_Applied; "
    "pre-admission cancellation reports "
    "Bucket_Inventory_Configuration_Mutation_Cancelled_Before_Admission; "
    "possible or incomplete admission, retryable responses, and malformed "
    "or oversized responses report "
    "Bucket_Inventory_Configuration_Mutation_Outcome_Unknown; no automatic "
    "replay"
)
DELETE_INVENTORY_RECONCILIATION = (
    "caller-selected Get_Inventory_Configuration for the same identifier may "
    "observe the current configuration or exact NoSuchConfiguration before "
    "a retry, but does not prove that the lost deletion caused the observed "
    "absence or upgrade mutation certainty; no automatic replay"
)
DELETE_INVENTORY_LANE = [
    [
        "uv", "run", "--python", "3.13", "--",
        "tools/verify-delete-bucket-configurations-preparation.py",
    ],
    ["@tests", "alr", "-n", "build"],
    ["@tests", "./bin/s3_delete_bucket_configurations_corpus"],
    ["@tests", "./bin/s3_http_socket_corpus"],
    ["./tools/verify-coverage.sh"],
    [
        "./tools/build-api-docs.sh",
        "/private/tmp/fos-delete-bucket-inventory-gnatdoc",
    ],
    ["./tools/ci/check-repository.sh", "{model}"],
    ["git", "diff", "--check"],
]
DELETE_METADATA_CERTAINTY = (
    "only a complete validated 204 response with an exactly empty body "
    "reports Bucket_Metadata_Configuration_Mutation_Completed; an exact "
    "recognized non-mutating rejection or definite non-admission reports "
    "Bucket_Metadata_Configuration_Mutation_Definitely_Not_Applied; "
    "pre-admission cancellation reports "
    "Bucket_Metadata_Configuration_Mutation_Cancelled_Before_Admission; "
    "possible or incomplete admission, retryable responses, and malformed "
    "or oversized responses report "
    "Bucket_Metadata_Configuration_Mutation_Outcome_Unknown; no automatic "
    "replay"
)
DELETE_METADATA_RECONCILIATION = (
    "caller-selected Get_Metadata_Configuration may observe the current "
    "modeled configuration response or structured rejection before a retry, "
    "but does not prove that the lost deletion caused the observation or "
    "upgrade mutation certainty; no automatic replay"
)
DELETE_METADATA_LANE = [
    [
        "uv", "run", "--python", "3.13", "--",
        "tools/verify-delete-bucket-configurations-preparation.py",
    ],
    ["@tests", "alr", "-n", "build"],
    ["@tests", "./bin/s3_delete_bucket_configurations_corpus"],
    ["@tests", "./bin/s3_http_socket_corpus"],
    ["./tools/verify-coverage.sh"],
    [
        "./tools/build-api-docs.sh",
        "/private/tmp/fos-delete-bucket-metadata-gnatdoc",
    ],
    ["./tools/ci/check-repository.sh", "{model}"],
    ["git", "diff", "--check"],
]
DELETE_METADATA_TABLE_CERTAINTY = (
    "only a complete validated 204 response with an exactly empty body "
    "reports Bucket_Metadata_Table_Mutation_Completed; an exact recognized "
    "non-mutating rejection or definite non-admission reports "
    "Bucket_Metadata_Table_Mutation_Definitely_Not_Applied; pre-admission "
    "cancellation reports "
    "Bucket_Metadata_Table_Mutation_Cancelled_Before_Admission; possible or "
    "incomplete admission, retryable responses, and malformed or oversized "
    "responses report Bucket_Metadata_Table_Mutation_Outcome_Unknown; no "
    "automatic replay"
)
DELETE_METADATA_TABLE_RECONCILIATION = (
    "caller-selected Get_Metadata_Table_Configuration may observe the "
    "current modeled configuration response or structured rejection before "
    "a retry, but does not prove that the lost deletion caused the "
    "observation or upgrade mutation certainty; no automatic replay"
)
DELETE_METADATA_TABLE_LANE = [
    [
        "uv", "run", "--python", "3.13", "--",
        "tools/verify-delete-bucket-configurations-preparation.py",
    ],
    ["@tests", "alr", "-n", "build"],
    ["@tests", "./bin/s3_delete_bucket_configurations_corpus"],
    ["@tests", "./bin/s3_http_socket_corpus"],
    ["./tools/verify-coverage.sh"],
    [
        "./tools/build-api-docs.sh",
        "/private/tmp/fos-delete-bucket-metadata-table-gnatdoc",
    ],
    ["./tools/ci/check-repository.sh", "{model}"],
    ["git", "diff", "--check"],
]
DELETE_METRICS_CERTAINTY = (
    "only a complete validated 204 response with an exactly empty body "
    "reports Bucket_Metrics_Configuration_Mutation_Completed; an exact "
    "recognized non-mutating rejection or definite non-admission reports "
    "Bucket_Metrics_Configuration_Mutation_Definitely_Not_Applied; "
    "pre-admission cancellation reports "
    "Bucket_Metrics_Configuration_Mutation_Cancelled_Before_Admission; "
    "possible or incomplete admission, retryable responses, and malformed "
    "or oversized responses report "
    "Bucket_Metrics_Configuration_Mutation_Outcome_Unknown; no automatic "
    "replay"
)
DELETE_METRICS_RECONCILIATION = (
    "caller-selected Get_Metrics_Configuration for the same identifier may "
    "observe the current configuration or exact NoSuchConfiguration before "
    "a retry, but does not prove that the lost deletion caused the observed "
    "absence or upgrade mutation certainty; no automatic replay"
)
DELETE_METRICS_LANE = [
    [
        "uv", "run", "--python", "3.13", "--",
        "tools/verify-delete-bucket-configurations-preparation.py",
    ],
    ["@tests", "alr", "-n", "build"],
    ["@tests", "./bin/s3_delete_bucket_configurations_corpus"],
    ["@tests", "./bin/s3_http_socket_corpus"],
    ["./tools/verify-coverage.sh"],
    [
        "./tools/build-api-docs.sh",
        "/private/tmp/fos-delete-bucket-metrics-gnatdoc",
    ],
    ["./tools/ci/check-repository.sh", "{model}"],
    ["git", "diff", "--check"],
]
DELETE_OWNERSHIP_CONTROLS_CERTAINTY = (
    "only a complete validated 204 response with an exactly empty body "
    "reports Bucket_Ownership_Controls_Mutation_Completed; an exact "
    "recognized non-mutating rejection or definite non-admission reports "
    "Bucket_Ownership_Controls_Mutation_Definitely_Not_Applied; "
    "pre-admission cancellation reports "
    "Bucket_Ownership_Controls_Mutation_Cancelled_Before_Admission; "
    "possible or incomplete admission, retryable responses, and malformed "
    "or oversized responses report "
    "Bucket_Ownership_Controls_Mutation_Outcome_Unknown; no automatic replay"
)
DELETE_OWNERSHIP_CONTROLS_RECONCILIATION = (
    "caller-selected Get_Ownership_Controls may observe the current "
    "ownership-controls configuration or exact "
    "OwnershipControlsNotFoundError before a retry, but does not prove that "
    "the lost deletion caused the observed absence or upgrade mutation "
    "certainty; no automatic replay"
)
DELETE_OWNERSHIP_CONTROLS_LANE = [
    [
        "uv", "run", "--python", "3.13", "--",
        "tools/verify-delete-bucket-configurations-preparation.py",
    ],
    ["@tests", "alr", "-n", "build"],
    ["@tests", "./bin/s3_delete_bucket_configurations_corpus"],
    ["@tests", "./bin/s3_http_socket_corpus"],
    ["./tools/verify-coverage.sh"],
    [
        "./tools/build-api-docs.sh",
        "/private/tmp/fos-delete-bucket-ownership-controls-gnatdoc",
    ],
    ["./tools/ci/check-repository.sh", "{model}"],
    ["git", "diff", "--check"],
]
DELETE_POLICY_CERTAINTY = (
    "only a complete validated 204 response with an exactly empty body "
    "reports Bucket_Policy_Mutation_Completed; an exact recognized "
    "non-mutating rejection or definite non-admission reports "
    "Bucket_Policy_Mutation_Definitely_Not_Applied; pre-admission "
    "cancellation reports Bucket_Policy_Mutation_Cancelled_Before_Admission; "
    "possible or incomplete admission, retryable responses, and malformed "
    "or oversized responses report Bucket_Policy_Mutation_Outcome_Unknown; "
    "no automatic replay"
)
DELETE_POLICY_RECONCILIATION = (
    "caller-selected Get_Policy may observe the current bucket policy or "
    "exact NoSuchBucketPolicy before a retry, but does not prove that the "
    "lost deletion caused the observed absence or upgrade mutation "
    "certainty; no automatic replay"
)
DELETE_POLICY_LANE = [
    [
        "uv", "run", "--python", "3.13", "--",
        "tools/verify-delete-bucket-configurations-preparation.py",
    ],
    ["@tests", "alr", "-n", "build"],
    ["@tests", "./bin/s3_delete_bucket_configurations_corpus"],
    ["@tests", "./bin/s3_server_application_corpus"],
    ["@tests", "./bin/s3_http_socket_corpus"],
    ["./tools/verify-coverage.sh"],
    [
        "./tools/build-api-docs.sh",
        "/private/tmp/fos-delete-bucket-policy-gnatdoc",
    ],
    ["./tools/ci/check-repository.sh", "{model}"],
    ["git", "diff", "--check"],
]
GET_POLICY_LANE = [
    [
        "uv", "run", "--python", "3.13", "--",
        "tools/verify-delete-bucket-configurations-preparation.py",
    ],
    ["@tests", "alr", "-n", "build"],
    ["@tests", "./bin/s3_get_bucket_controls_corpus"],
    ["@tests", "./bin/s3_server_application_corpus"],
    ["@tests", "./bin/s3_http_socket_corpus"],
    ["./tools/verify-coverage.sh"],
    [
        "./tools/build-api-docs.sh",
        "/private/tmp/fos-get-bucket-policy-gnatdoc",
    ],
    ["./tools/ci/check-repository.sh", "{model}"],
    ["git", "diff", "--check"],
]
PUT_POLICY_CERTAINTY = (
    "only a complete validated 200 response with an empty or whitespace-only "
    "body reports Bucket_Policy_Mutation_Completed; an exact recognized "
    "non-mutating rejection or definite non-admission reports "
    "Bucket_Policy_Mutation_Definitely_Not_Applied; pre-admission "
    "cancellation reports Bucket_Policy_Mutation_Cancelled_Before_Admission; "
    "possible or incomplete admission, retryable responses, and malformed "
    "or oversized responses report Bucket_Policy_Mutation_Outcome_Unknown; "
    "no automatic replay"
)
PUT_POLICY_RECONCILIATION = (
    "caller-selected Get_Policy may observe the current exact policy bytes "
    "or NoSuchBucketPolicy before a retry, but does not prove that the lost "
    "replacement caused the observed state or upgrade mutation certainty; "
    "no automatic replay"
)
PUT_POLICY_LANE = [
    [
        "uv", "run", "--python", "3.13", "--",
        "tools/verify-delete-bucket-configurations-preparation.py",
    ],
    ["@tests", "alr", "-n", "build"],
    ["@tests", "./bin/s3_put_bucket_controls_corpus"],
    ["@tests", "./bin/s3_server_application_corpus"],
    ["@tests", "./bin/s3_http_socket_corpus"],
    ["./tools/verify-coverage.sh"],
    [
        "./tools/build-api-docs.sh",
        "/private/tmp/fos-put-bucket-policy-gnatdoc",
    ],
    ["./tools/ci/check-repository.sh", "{model}"],
    ["git", "diff", "--check"],
]
DELETE_PUBLIC_ACCESS_BLOCK_CERTAINTY = (
    "only a complete validated 204 response with an exactly empty body "
    "reports Public_Access_Block_Mutation_Completed; an exact recognized "
    "non-mutating rejection or definite non-admission reports "
    "Public_Access_Block_Mutation_Definitely_Not_Applied; pre-admission "
    "cancellation reports "
    "Public_Access_Block_Mutation_Cancelled_Before_Admission; possible or "
    "incomplete admission, retryable responses, and malformed or oversized "
    "responses report Public_Access_Block_Mutation_Outcome_Unknown; no "
    "automatic replay"
)
DELETE_PUBLIC_ACCESS_BLOCK_RECONCILIATION = (
    "caller-selected Get_Public_Access_Block may observe the current bucket "
    "public-access-block configuration or exact "
    "NoSuchPublicAccessBlockConfiguration before a retry, but does not prove "
    "that the lost deletion caused the observed absence or upgrade mutation "
    "certainty; no automatic replay"
)
DELETE_PUBLIC_ACCESS_BLOCK_LANE = [
    [
        "uv", "run", "--python", "3.13", "--",
        "tools/verify-delete-bucket-configurations-preparation.py",
    ],
    ["@tests", "alr", "-n", "build"],
    ["@tests", "./bin/s3_delete_bucket_configurations_corpus"],
    ["@tests", "./bin/s3_server_application_corpus"],
    ["@tests", "./bin/s3_http_socket_corpus"],
    ["./tools/verify-coverage.sh"],
    [
        "./tools/build-api-docs.sh",
        "/private/tmp/fos-delete-public-access-block-gnatdoc",
    ],
    ["./tools/ci/check-repository.sh", "{model}"],
    ["git", "diff", "--check"],
]
GET_PUBLIC_ACCESS_BLOCK_LANE = [
    [
        "uv", "run", "--python", "3.13", "--",
        "tools/verify-delete-bucket-configurations-preparation.py",
    ],
    ["@tests", "alr", "-n", "build"],
    ["@tests", "./bin/s3_get_bucket_controls_corpus"],
    ["@tests", "./bin/s3_server_application_corpus"],
    ["@tests", "./bin/s3_http_socket_corpus"],
    ["./tools/verify-coverage.sh"],
    [
        "./tools/build-api-docs.sh",
        "/private/tmp/fos-get-public-access-block-gnatdoc",
    ],
    ["./tools/ci/check-repository.sh", "{model}"],
    ["git", "diff", "--check"],
]
PUT_PUBLIC_ACCESS_BLOCK_CERTAINTY = (
    "only a complete validated 200 response with an empty or whitespace-only "
    "body reports Public_Access_Block_Mutation_Completed; an exact recognized "
    "non-mutating rejection or definite non-admission reports "
    "Public_Access_Block_Mutation_Definitely_Not_Applied; pre-admission "
    "cancellation reports "
    "Public_Access_Block_Mutation_Cancelled_Before_Admission; possible or "
    "incomplete admission, retryable responses, and malformed or oversized "
    "responses report Public_Access_Block_Mutation_Outcome_Unknown; no "
    "automatic replay"
)
PUT_PUBLIC_ACCESS_BLOCK_RECONCILIATION = (
    "caller-selected Get_Public_Access_Block may observe the current bucket "
    "public-access-block configuration or exact "
    "NoSuchPublicAccessBlockConfiguration before a retry, but does not prove "
    "that the lost replacement caused the observed state or upgrade mutation "
    "certainty; no automatic replay"
)
PUT_PUBLIC_ACCESS_BLOCK_LANE = [
    [
        "uv", "run", "--python", "3.13", "--",
        "tools/verify-delete-bucket-configurations-preparation.py",
    ],
    ["@tests", "alr", "-n", "build"],
    ["@tests", "./bin/s3_put_bucket_controls_corpus"],
    ["@tests", "./bin/s3_server_application_corpus"],
    ["@tests", "./bin/s3_http_socket_corpus"],
    ["./tools/verify-coverage.sh"],
    [
        "./tools/build-api-docs.sh",
        "/private/tmp/fos-put-public-access-block-gnatdoc",
    ],
    ["./tools/ci/check-repository.sh", "{model}"],
    ["git", "diff", "--check"],
]

# Operation, generated enum stem, shape, URI, whether Id is required,
# low-level preparer, low-level executor, and convenience call.
EXPECTED = [
    ("DeleteBucketAnalyticsConfiguration", "Delete_Bucket_Analytics_Configuration", 145,
     "/{Bucket}?analytics", True, "Prepare_Delete_Bucket_Analytics_Configuration",
     "Execute_Delete_Bucket_Analytics_Configuration", "Delete_Analytics_Configuration"),
    ("DeleteBucketEncryption", "Delete_Bucket_Encryption", 147,
     "/{Bucket}?encryption", False, "Prepare_Delete_Bucket_Encryption",
     "Execute_Delete_Bucket_Encryption", "Delete_Encryption"),
    ("DeleteBucketIntelligentTieringConfiguration",
     "Delete_Bucket_Intelligent_Tiering_Configuration", 148,
     "/{Bucket}?intelligent-tiering", True,
     "Prepare_Delete_Bucket_Intelligent_Tiering_Configuration",
     "Execute_Delete_Bucket_Intelligent_Tiering_Configuration",
     "Delete_Intelligent_Tiering_Configuration"),
    ("DeleteBucketInventoryConfiguration", "Delete_Bucket_Inventory_Configuration", 149,
     "/{Bucket}?inventory", True, "Prepare_Delete_Bucket_Inventory_Configuration",
     "Execute_Delete_Bucket_Inventory_Configuration", "Delete_Inventory_Configuration"),
    ("DeleteBucketLifecycle", "Delete_Bucket_Lifecycle", 150,
     "/{Bucket}?lifecycle", False, "Prepare_Delete_Bucket_Lifecycle",
     "Execute_Delete_Bucket_Lifecycle", "Delete_Lifecycle"),
    ("DeleteBucketMetadataConfiguration", "Delete_Bucket_Metadata_Configuration", 151,
     "/{Bucket}?metadataConfiguration", False,
     "Prepare_Delete_Bucket_Metadata_Configuration",
     "Execute_Delete_Bucket_Metadata_Configuration", "Delete_Metadata_Configuration"),
    ("DeleteBucketMetadataTableConfiguration",
     "Delete_Bucket_Metadata_Table_Configuration", 152,
     "/{Bucket}?metadataTable", False,
     "Prepare_Delete_Bucket_Metadata_Table_Configuration",
     "Execute_Delete_Bucket_Metadata_Table_Configuration",
     "Delete_Metadata_Table_Configuration"),
    ("DeleteBucketMetricsConfiguration", "Delete_Bucket_Metrics_Configuration", 153,
     "/{Bucket}?metrics", True, "Prepare_Delete_Bucket_Metrics_Configuration",
     "Execute_Delete_Bucket_Metrics_Configuration", "Delete_Metrics_Configuration"),
    ("DeleteBucketOwnershipControls", "Delete_Bucket_Ownership_Controls", 154,
     "/{Bucket}?ownershipControls", False,
     "Prepare_Delete_Bucket_Ownership_Controls",
     "Execute_Delete_Bucket_Ownership_Controls", "Delete_Ownership_Controls"),
    ("DeleteBucketPolicy", "Delete_Bucket_Policy", 155,
     "/{Bucket}?policy", False, "Prepare_Delete_Bucket_Policy",
     "Execute_Delete_Bucket_Policy", "Delete_Policy"),
    ("DeleteBucketReplication", "Delete_Bucket_Replication", 156,
     "/{Bucket}?replication", False, "Prepare_Delete_Bucket_Replication",
     "Execute_Delete_Bucket_Replication", "Delete_Replication"),
    ("DeleteBucketWebsite", "Delete_Bucket_Website", 159,
     "/{Bucket}?website", False, "Prepare_Delete_Bucket_Website",
     "Execute_Delete_Bucket_Website", "Delete_Website"),
    ("DeletePublicAccessBlock", "Delete_Public_Access_Block", 174,
     "/{Bucket}?publicAccessBlock", False, "Prepare_Delete_Public_Access_Block",
     "Execute_Delete_Public_Access_Block", "Delete_Public_Access_Block"),
]

OP_HEADER = [
    "operation", "input_shape", "request_uri", "identifier_required",
    "member_count", "prepare", "execute", "high_level", "vector_ids",
]
MEMBER_HEADER = [
    "operation", "shape", "ordinal", "member", "wire_location", "required",
    "vector_ids",
]
VECTOR_HEADER = [
    "id", "direction", "layer", "category", "operation_refs", "stimulus",
    "expected_contract",
]
LOCATION = {
    "Bucket": "URI_Location",
    "Id": "Query_Location",
    "ExpectedBucketOwner": "Header_Location",
}


def fail(message: str) -> None:
    raise ValueError(message)


def ordered(text: str, markers: list[str], label: str) -> None:
    cursor = 0
    for marker in markers:
        position = text.find(marker, cursor)
        if position < 0:
            fail(f"{label}: missing ordered marker: {marker}")
        cursor = position + len(marker)


def delete_encryption_entry(data: dict[str, object]) -> dict[str, object]:
    matches = [
        entry for entry in data["operation"]
        if entry["name"] == "DeleteBucketEncryption"
    ]
    if len(matches) != 1:
        fail("DeleteBucketEncryption registry entry is not unique")
    return matches[0]


def verify_delete_encryption_registry(data: dict[str, object]) -> None:
    entry = delete_encryption_entry(data)
    expected = {
        "public_name": "Delete_Encryption",
        "decision_status": "reviewed",
        "human_decisions_resolved": True,
        "qualification": "delete_bucket_encryption",
        "codec": "empty_response",
        "certainty": DELETE_ENCRYPTION_CERTAINTY,
        "reconciliation": DELETE_ENCRYPTION_RECONCILIATION,
        "coverage": {
            "backend": "covered",
            "client": "covered",
            "server": "covered",
            "corpus": "covered",
        },
        "ada_symbols": [
            "Prepare_Delete_Bucket_Encryption",
            "Execute_Delete_Bucket_Encryption",
            "Delete_Bucket_Encryption_Operation",
            "Delete_Encryption",
            "Finish",
        ],
    }
    for key, value in expected.items():
        if entry.get(key) != value:
            fail(f"DeleteBucketEncryption registry changed: {key}")
    if "resets bucket default encryption to SSE-S3" not in entry["absence"]:
        fail("DeleteBucketEncryption reset semantics changed")
    if "exact HTTP 204" not in entry["exclusions"][1]:
        fail("DeleteBucketEncryption success status changed")
    if "does not establish an absent configuration" not in (
        entry["exclusions"][2]
    ):
        fail("DeleteBucketEncryption absence boundary changed")
    if data["qualification"].get("delete_bucket_encryption") != (
        DELETE_ENCRYPTION_LANE
    ):
        fail("DeleteBucketEncryption qualification lane changed")


def verify_delete_encryption_negatives(data: dict[str, object]) -> None:
    mutations = (
        ("missing public name", "public_name", None),
        ("wrong public name", "public_name", "Delete_CORS"),
        (
            "broadened success",
            "certainty",
            DELETE_ENCRYPTION_CERTAINTY.replace(
                "validated 204", "validated 200 or 204"
            ),
        ),
        (
            "causal reconciliation",
            "reconciliation",
            "Get_Encryption proves the reset completed",
        ),
        ("cross-operation lane", "qualification", "delete_bucket_cors"),
    )
    for label, key, value in mutations:
        candidate = copy.deepcopy(data)
        entry = delete_encryption_entry(candidate)
        if value is None:
            del entry[key]
        else:
            entry[key] = value
        if candidate == data:
            fail(f"{label}: candidate did not change")
        try:
            verify_delete_encryption_registry(candidate)
        except (KeyError, TypeError, ValueError):
            continue
        fail(f"{label}: candidate was accepted")


def delete_lifecycle_entry(data: dict[str, object]) -> dict[str, object]:
    matches = [
        entry for entry in data["operation"]
        if entry["name"] == "DeleteBucketLifecycle"
    ]
    if len(matches) != 1:
        fail("DeleteBucketLifecycle registry entry is not unique")
    return matches[0]


def verify_delete_lifecycle_registry(data: dict[str, object]) -> None:
    entry = delete_lifecycle_entry(data)
    expected = {
        "public_name": "Delete_Lifecycle",
        "decision_status": "reviewed",
        "human_decisions_resolved": True,
        "qualification": "delete_bucket_lifecycle",
        "codec": "empty_response",
        "certainty": DELETE_LIFECYCLE_CERTAINTY,
        "reconciliation": DELETE_LIFECYCLE_RECONCILIATION,
        "coverage": {
            "backend": "covered",
            "client": "covered",
            "server": "covered",
            "corpus": "covered",
        },
        "ada_symbols": [
            "Prepare_Delete_Bucket_Lifecycle",
            "Execute_Delete_Bucket_Lifecycle",
            "Delete_Bucket_Lifecycle_Operation",
            "Delete_Lifecycle",
            "Finish",
        ],
    }
    for key, value in expected.items():
        if entry.get(key) != value:
            fail(f"DeleteBucketLifecycle registry changed: {key}")
    if "removes all lifecycle configuration rules" not in entry["absence"]:
        fail("DeleteBucketLifecycle deletion semantics changed")
    if "exact HTTP 204" not in entry["exclusions"][1]:
        fail("DeleteBucketLifecycle success status changed")
    if "does not establish causation" not in entry["exclusions"][2]:
        fail("DeleteBucketLifecycle reconciliation boundary changed")
    if data["qualification"].get("delete_bucket_lifecycle") != (
        DELETE_LIFECYCLE_LANE
    ):
        fail("DeleteBucketLifecycle qualification lane changed")


def verify_delete_lifecycle_negatives(data: dict[str, object]) -> None:
    mutations = (
        ("missing public name", "public_name", None),
        ("wrong public name", "public_name", "Delete_Encryption"),
        (
            "broadened success",
            "certainty",
            DELETE_LIFECYCLE_CERTAINTY.replace(
                "validated 204", "validated 200 or 204"
            ),
        ),
        (
            "causal reconciliation",
            "reconciliation",
            "Get_Lifecycle_Configuration proves the deletion completed",
        ),
        ("cross-operation lane", "qualification", "delete_bucket_encryption"),
    )
    for label, key, value in mutations:
        candidate = copy.deepcopy(data)
        entry = delete_lifecycle_entry(candidate)
        if value is None:
            del entry[key]
        else:
            entry[key] = value
        if candidate == data:
            fail(f"{label}: candidate did not change")
        try:
            verify_delete_lifecycle_registry(candidate)
        except (KeyError, TypeError, ValueError):
            continue
        fail(f"{label}: candidate was accepted")


def delete_replication_entry(data: dict[str, object]) -> dict[str, object]:
    matches = [
        entry for entry in data["operation"]
        if entry["name"] == "DeleteBucketReplication"
    ]
    if len(matches) != 1:
        fail("DeleteBucketReplication registry entry is not unique")
    return matches[0]


def verify_delete_replication_registry(data: dict[str, object]) -> None:
    entry = delete_replication_entry(data)
    expected = {
        "public_name": "Delete_Replication",
        "decision_status": "reviewed",
        "human_decisions_resolved": True,
        "qualification": "delete_bucket_replication",
        "codec": "empty_response",
        "certainty": DELETE_REPLICATION_CERTAINTY,
        "reconciliation": DELETE_REPLICATION_RECONCILIATION,
        "coverage": {
            "backend": "missing",
            "client": "covered",
            "server": "missing",
            "corpus": "covered",
        },
        "ada_symbols": [
            "Prepare_Delete_Bucket_Replication",
            "Execute_Delete_Bucket_Replication",
            "Delete_Bucket_Replication_Operation",
            "Delete_Replication",
            "Finish",
        ],
    }
    for key, value in expected.items():
        if entry.get(key) != value:
            fail(f"DeleteBucketReplication registry changed: {key}")
    if "removes the bucket replication configuration" not in entry["absence"]:
        fail("DeleteBucketReplication deletion semantics changed")
    if "exact HTTP 204" not in entry["exclusions"][2]:
        fail("DeleteBucketReplication success status changed")
    if "does not establish causation" not in entry["exclusions"][3]:
        fail("DeleteBucketReplication reconciliation boundary changed")
    if data["qualification"].get("delete_bucket_replication") != (
        DELETE_REPLICATION_LANE
    ):
        fail("DeleteBucketReplication qualification lane changed")


def verify_delete_replication_negatives(data: dict[str, object]) -> None:
    mutations = (
        ("missing public name", "public_name", None),
        ("wrong public name", "public_name", "Delete_Lifecycle"),
        (
            "broadened success",
            "certainty",
            DELETE_REPLICATION_CERTAINTY.replace(
                "validated 204", "validated 200 or 204"
            ),
        ),
        (
            "causal reconciliation",
            "reconciliation",
            "Get_Replication_Configuration proves the deletion completed",
        ),
        ("cross-operation lane", "qualification", "delete_bucket_lifecycle"),
    )
    for label, key, value in mutations:
        candidate = copy.deepcopy(data)
        entry = delete_replication_entry(candidate)
        if value is None:
            del entry[key]
        else:
            entry[key] = value
        if candidate == data:
            fail(f"{label}: candidate did not change")
        try:
            verify_delete_replication_registry(candidate)
        except (KeyError, TypeError, ValueError):
            continue
        fail(f"{label}: candidate was accepted")


def delete_website_entry(data: dict[str, object]) -> dict[str, object]:
    matches = [
        entry for entry in data["operation"]
        if entry["name"] == "DeleteBucketWebsite"
    ]
    if len(matches) != 1:
        fail("DeleteBucketWebsite registry entry is not unique")
    return matches[0]


def verify_delete_website_registry(data: dict[str, object]) -> None:
    entry = delete_website_entry(data)
    expected = {
        "public_name": "Delete_Website",
        "decision_status": "reviewed",
        "human_decisions_resolved": True,
        "qualification": "delete_bucket_website",
        "codec": "empty_response",
        "certainty": DELETE_WEBSITE_CERTAINTY,
        "reconciliation": DELETE_WEBSITE_RECONCILIATION,
        "coverage": {
            "backend": "missing",
            "client": "covered",
            "server": "missing",
            "corpus": "covered",
        },
        "ada_symbols": [
            "Prepare_Delete_Bucket_Website",
            "Execute_Delete_Bucket_Website",
            "Delete_Bucket_Website_Operation",
            "Delete_Website",
            "Finish",
        ],
    }
    for key, value in expected.items():
        if entry.get(key) != value:
            fail(f"DeleteBucketWebsite registry changed: {key}")
    if "removes the bucket website configuration" not in entry["absence"]:
        fail("DeleteBucketWebsite deletion semantics changed")
    if "exact HTTP 204" not in entry["exclusions"][2]:
        fail("DeleteBucketWebsite success status changed")
    if "previously present" not in entry["exclusions"][3]:
        fail("DeleteBucketWebsite prior-presence boundary changed")
    if "does not establish causation" not in entry["exclusions"][4]:
        fail("DeleteBucketWebsite reconciliation boundary changed")
    if data["qualification"].get("delete_bucket_website") != (
        DELETE_WEBSITE_LANE
    ):
        fail("DeleteBucketWebsite qualification lane changed")


def verify_delete_website_negatives(data: dict[str, object]) -> None:
    mutations = (
        ("missing public name", "public_name", None),
        ("wrong public name", "public_name", "Delete_Replication"),
        (
            "broadened success",
            "certainty",
            DELETE_WEBSITE_CERTAINTY.replace(
                "validated 204", "validated 200 or 204"
            ),
        ),
        (
            "causal reconciliation",
            "reconciliation",
            "Get_Website proves the deletion completed",
        ),
        ("cross-operation lane", "qualification", "delete_bucket_replication"),
    )
    for label, key, value in mutations:
        candidate = copy.deepcopy(data)
        entry = delete_website_entry(candidate)
        if value is None:
            del entry[key]
        else:
            entry[key] = value
        if candidate == data:
            fail(f"{label}: candidate did not change")
        try:
            verify_delete_website_registry(candidate)
        except (KeyError, TypeError, ValueError):
            continue
        fail(f"{label}: candidate was accepted")


def delete_analytics_entry(data: dict[str, object]) -> dict[str, object]:
    matches = [
        entry for entry in data["operation"]
        if entry["name"] == "DeleteBucketAnalyticsConfiguration"
    ]
    if len(matches) != 1:
        fail("DeleteBucketAnalyticsConfiguration registry entry is not unique")
    return matches[0]


def verify_delete_analytics_registry(data: dict[str, object]) -> None:
    entry = delete_analytics_entry(data)
    expected = {
        "public_name": "Delete_Analytics_Configuration",
        "decision_status": "reviewed",
        "human_decisions_resolved": True,
        "qualification": "delete_bucket_analytics",
        "codec": "empty_response",
        "certainty": DELETE_ANALYTICS_CERTAINTY,
        "reconciliation": DELETE_ANALYTICS_RECONCILIATION,
        "coverage": {
            "backend": "missing",
            "client": "covered",
            "server": "missing",
            "corpus": "covered",
        },
        "ada_symbols": [
            "Prepare_Delete_Bucket_Analytics_Configuration",
            "Execute_Delete_Bucket_Analytics_Configuration",
            "Delete_Bucket_Analytics_Operation",
            "Delete_Analytics_Configuration",
            "Finish",
        ],
    }
    for key, value in expected.items():
        if entry.get(key) != value:
            fail(f"DeleteBucketAnalyticsConfiguration changed: {key}")
    if "removes the selected bucket analytics" not in entry["absence"]:
        fail("DeleteBucketAnalyticsConfiguration semantics changed")
    if "exact HTTP 204" not in entry["exclusions"][2]:
        fail("DeleteBucketAnalyticsConfiguration success changed")
    if "previously present" not in entry["exclusions"][3]:
        fail("DeleteBucketAnalyticsConfiguration presence claim changed")
    if "does not establish causation" not in entry["exclusions"][4]:
        fail("DeleteBucketAnalyticsConfiguration reconciliation changed")
    if data["qualification"].get("delete_bucket_analytics") != (
        DELETE_ANALYTICS_LANE
    ):
        fail("DeleteBucketAnalyticsConfiguration lane changed")


def verify_delete_analytics_negatives(data: dict[str, object]) -> None:
    mutations = (
        ("missing public name", "public_name", None),
        ("wrong public name", "public_name", "Delete_Website"),
        (
            "broadened success",
            "certainty",
            DELETE_ANALYTICS_CERTAINTY.replace(
                "validated 204", "validated 200 or 204"
            ),
        ),
        (
            "causal reconciliation",
            "reconciliation",
            "Get_Analytics_Configuration proves deletion completed",
        ),
        ("cross-operation lane", "qualification", "delete_bucket_website"),
    )
    for label, key, value in mutations:
        candidate = copy.deepcopy(data)
        entry = delete_analytics_entry(candidate)
        if value is None:
            del entry[key]
        else:
            entry[key] = value
        if candidate == data:
            fail(f"{label}: candidate did not change")
        try:
            verify_delete_analytics_registry(candidate)
        except (KeyError, TypeError, ValueError):
            continue
        fail(f"{label}: candidate was accepted")


def intelligent_tiering_entry(data: dict[str, object]) -> dict[str, object]:
    matches = [
        entry for entry in data["operation"]
        if entry["name"] == "DeleteBucketIntelligentTieringConfiguration"
    ]
    if len(matches) != 1:
        fail("DeleteBucketIntelligentTieringConfiguration is not unique")
    return matches[0]


def verify_intelligent_tiering_registry(data: dict[str, object]) -> None:
    entry = intelligent_tiering_entry(data)
    expected = {
        "public_name": "Delete_Intelligent_Tiering_Configuration",
        "decision_status": "reviewed",
        "human_decisions_resolved": True,
        "qualification": "delete_bucket_intelligent_tiering",
        "codec": "empty_response",
        "certainty": DELETE_INTELLIGENT_TIERING_CERTAINTY,
        "reconciliation": DELETE_INTELLIGENT_TIERING_RECONCILIATION,
        "coverage": {
            "backend": "missing",
            "client": "covered",
            "server": "missing",
            "corpus": "covered",
        },
        "ada_symbols": [
            "Prepare_Delete_Bucket_Intelligent_Tiering_Configuration",
            "Execute_Delete_Bucket_Intelligent_Tiering_Configuration",
            "Delete_Bucket_Tiering_Operation",
            "Delete_Intelligent_Tiering_Configuration",
            "Finish",
        ],
    }
    for key, value in expected.items():
        if entry.get(key) != value:
            fail(f"DeleteBucketIntelligentTieringConfiguration changed: {key}")
    if "removes the selected bucket intelligent-tiering" not in entry[
        "absence"
    ]:
        fail("DeleteBucketIntelligentTieringConfiguration semantics changed")
    if "exact HTTP 204" not in entry["exclusions"][2]:
        fail("DeleteBucketIntelligentTieringConfiguration success changed")
    if "previously present" not in entry["exclusions"][3]:
        fail("DeleteBucketIntelligentTieringConfiguration presence changed")
    if "does not establish causation" not in entry["exclusions"][4]:
        fail("DeleteBucketIntelligentTieringConfiguration reconcile changed")
    if data["qualification"].get(
        "delete_bucket_intelligent_tiering"
    ) != DELETE_INTELLIGENT_TIERING_LANE:
        fail("DeleteBucketIntelligentTieringConfiguration lane changed")


def verify_intelligent_tiering_negatives(data: dict[str, object]) -> None:
    mutations = (
        ("missing public name", "public_name", None),
        ("wrong public name", "public_name", "Delete_Analytics_Configuration"),
        (
            "broadened success",
            "certainty",
            DELETE_INTELLIGENT_TIERING_CERTAINTY.replace(
                "validated 204", "validated 200 or 204"
            ),
        ),
        (
            "causal reconciliation",
            "reconciliation",
            "Get_Intelligent_Tiering_Configuration proves deletion",
        ),
        ("cross-operation lane", "qualification", "delete_bucket_analytics"),
    )
    for label, key, value in mutations:
        candidate = copy.deepcopy(data)
        entry = intelligent_tiering_entry(candidate)
        if value is None:
            del entry[key]
        else:
            entry[key] = value
        if candidate == data:
            fail(f"{label}: candidate did not change")
        try:
            verify_intelligent_tiering_registry(candidate)
        except (KeyError, TypeError, ValueError):
            continue
        fail(f"{label}: candidate was accepted")


def inventory_entry(data: dict[str, object]) -> dict[str, object]:
    matches = [
        entry for entry in data["operation"]
        if entry["name"] == "DeleteBucketInventoryConfiguration"
    ]
    if len(matches) != 1:
        fail("DeleteBucketInventoryConfiguration is not unique")
    return matches[0]


def verify_inventory_registry(data: dict[str, object]) -> None:
    entry = inventory_entry(data)
    expected = {
        "public_name": "Delete_Inventory_Configuration",
        "decision_status": "reviewed",
        "human_decisions_resolved": True,
        "qualification": "delete_bucket_inventory",
        "codec": "empty_response",
        "certainty": DELETE_INVENTORY_CERTAINTY,
        "reconciliation": DELETE_INVENTORY_RECONCILIATION,
        "coverage": {
            "backend": "missing",
            "client": "covered",
            "server": "missing",
            "corpus": "covered",
        },
        "ada_symbols": [
            "Prepare_Delete_Bucket_Inventory_Configuration",
            "Execute_Delete_Bucket_Inventory_Configuration",
            "Delete_Bucket_Inventory_Configuration_Operation",
            "Delete_Inventory_Configuration",
            "Finish",
        ],
    }
    for key, value in expected.items():
        if entry.get(key) != value:
            fail(f"DeleteBucketInventoryConfiguration changed: {key}")
    if "removes the selected bucket inventory" not in entry["absence"]:
        fail("DeleteBucketInventoryConfiguration semantics changed")
    if "exact HTTP 204" not in entry["exclusions"][2]:
        fail("DeleteBucketInventoryConfiguration success changed")
    if "previously present" not in entry["exclusions"][3]:
        fail("DeleteBucketInventoryConfiguration presence changed")
    if "does not establish causation" not in entry["exclusions"][4]:
        fail("DeleteBucketInventoryConfiguration reconcile changed")
    if data["qualification"].get(
        "delete_bucket_inventory"
    ) != DELETE_INVENTORY_LANE:
        fail("DeleteBucketInventoryConfiguration lane changed")


def verify_inventory_negatives(data: dict[str, object]) -> None:
    mutations = (
        ("missing public name", "public_name", None),
        (
            "wrong public name",
            "public_name",
            "Delete_Intelligent_Tiering_Configuration",
        ),
        (
            "broadened success",
            "certainty",
            DELETE_INVENTORY_CERTAINTY.replace(
                "validated 204", "validated 200 or 204"
            ),
        ),
        (
            "causal reconciliation",
            "reconciliation",
            "Get_Inventory_Configuration proves deletion",
        ),
        (
            "cross-operation lane",
            "qualification",
            "delete_bucket_intelligent_tiering",
        ),
    )
    for label, key, value in mutations:
        candidate = copy.deepcopy(data)
        entry = inventory_entry(candidate)
        if value is None:
            del entry[key]
        else:
            entry[key] = value
        if candidate == data:
            fail(f"{label}: candidate did not change")
        try:
            verify_inventory_registry(candidate)
        except (KeyError, TypeError, ValueError):
            continue
        fail(f"{label}: candidate was accepted")


def metadata_entry(data: dict[str, object]) -> dict[str, object]:
    matches = [
        entry for entry in data["operation"]
        if entry["name"] == "DeleteBucketMetadataConfiguration"
    ]
    if len(matches) != 1:
        fail("DeleteBucketMetadataConfiguration is not unique")
    return matches[0]


def verify_metadata_registry(data: dict[str, object]) -> None:
    entry = metadata_entry(data)
    expected = {
        "public_name": "Delete_Metadata_Configuration",
        "decision_status": "reviewed",
        "human_decisions_resolved": True,
        "qualification": "delete_bucket_metadata",
        "codec": "empty_response",
        "certainty": DELETE_METADATA_CERTAINTY,
        "reconciliation": DELETE_METADATA_RECONCILIATION,
        "coverage": {
            "backend": "missing",
            "client": "covered",
            "server": "missing",
            "corpus": "covered",
        },
        "ada_symbols": [
            "Prepare_Delete_Bucket_Metadata_Configuration",
            "Execute_Delete_Bucket_Metadata_Configuration",
            "Delete_Bucket_Metadata_Operation",
            "Delete_Metadata_Configuration",
            "Finish",
        ],
    }
    for key, value in expected.items():
        if entry.get(key) != value:
            fail(f"DeleteBucketMetadataConfiguration changed: {key}")
    if "removes the bucket metadata" not in entry["absence"]:
        fail("DeleteBucketMetadataConfiguration semantics changed")
    if "exact HTTP 204" not in entry["exclusions"][2]:
        fail("DeleteBucketMetadataConfiguration success changed")
    if "previously present" not in entry["exclusions"][3]:
        fail("DeleteBucketMetadataConfiguration presence changed")
    if "does not establish causation" not in entry["exclusions"][4]:
        fail("DeleteBucketMetadataConfiguration reconcile changed")
    if data["qualification"].get(
        "delete_bucket_metadata"
    ) != DELETE_METADATA_LANE:
        fail("DeleteBucketMetadataConfiguration lane changed")


def verify_metadata_negatives(data: dict[str, object]) -> None:
    mutations = (
        ("missing public name", "public_name", None),
        (
            "wrong public name",
            "public_name",
            "Delete_Inventory_Configuration",
        ),
        (
            "broadened success",
            "certainty",
            DELETE_METADATA_CERTAINTY.replace(
                "validated 204", "validated 200 or 204"
            ),
        ),
        (
            "causal reconciliation",
            "reconciliation",
            "Get_Metadata_Configuration proves deletion",
        ),
        (
            "cross-operation lane",
            "qualification",
            "delete_bucket_inventory",
        ),
    )
    for label, key, value in mutations:
        candidate = copy.deepcopy(data)
        entry = metadata_entry(candidate)
        if value is None:
            del entry[key]
        else:
            entry[key] = value
        if candidate == data:
            fail(f"{label}: candidate did not change")
        try:
            verify_metadata_registry(candidate)
        except (KeyError, TypeError, ValueError):
            continue
        fail(f"{label}: candidate was accepted")


def metadata_table_entry(data: dict[str, object]) -> dict[str, object]:
    matches = [
        entry for entry in data["operation"]
        if entry["name"] == "DeleteBucketMetadataTableConfiguration"
    ]
    if len(matches) != 1:
        fail("DeleteBucketMetadataTableConfiguration is not unique")
    return matches[0]


def verify_metadata_table_registry(data: dict[str, object]) -> None:
    entry = metadata_table_entry(data)
    expected = {
        "public_name": "Delete_Metadata_Table_Configuration",
        "decision_status": "reviewed",
        "human_decisions_resolved": True,
        "qualification": "delete_bucket_metadata_table",
        "codec": "empty_response",
        "certainty": DELETE_METADATA_TABLE_CERTAINTY,
        "reconciliation": DELETE_METADATA_TABLE_RECONCILIATION,
        "coverage": {
            "backend": "missing",
            "client": "covered",
            "server": "missing",
            "corpus": "covered",
        },
        "ada_symbols": [
            "Prepare_Delete_Bucket_Metadata_Table_Configuration",
            "Execute_Delete_Bucket_Metadata_Table_Configuration",
            "Delete_Bucket_Metadata_Table_Operation",
            "Delete_Metadata_Table_Configuration",
            "Finish",
        ],
    }
    for key, value in expected.items():
        if entry.get(key) != value:
            fail(f"DeleteBucketMetadataTableConfiguration changed: {key}")
    if "removes the bucket metadata-table" not in entry["absence"]:
        fail("DeleteBucketMetadataTableConfiguration semantics changed")
    if "exact HTTP 204" not in entry["exclusions"][2]:
        fail("DeleteBucketMetadataTableConfiguration success changed")
    if "previously present" not in entry["exclusions"][3]:
        fail("DeleteBucketMetadataTableConfiguration presence changed")
    if "does not establish causation" not in entry["exclusions"][4]:
        fail("DeleteBucketMetadataTableConfiguration reconcile changed")
    if data["qualification"].get(
        "delete_bucket_metadata_table"
    ) != DELETE_METADATA_TABLE_LANE:
        fail("DeleteBucketMetadataTableConfiguration lane changed")


def verify_metadata_table_negatives(data: dict[str, object]) -> None:
    mutations = (
        ("missing public name", "public_name", None),
        (
            "wrong public name",
            "public_name",
            "Delete_Metadata_Configuration",
        ),
        (
            "broadened success",
            "certainty",
            DELETE_METADATA_TABLE_CERTAINTY.replace(
                "validated 204", "validated 200 or 204"
            ),
        ),
        (
            "causal reconciliation",
            "reconciliation",
            "Get_Metadata_Table_Configuration proves deletion",
        ),
        (
            "cross-operation lane",
            "qualification",
            "delete_bucket_metadata",
        ),
    )
    for label, key, value in mutations:
        candidate = copy.deepcopy(data)
        entry = metadata_table_entry(candidate)
        if value is None:
            del entry[key]
        else:
            entry[key] = value
        if candidate == data:
            fail(f"{label}: candidate did not change")
        try:
            verify_metadata_table_registry(candidate)
        except (KeyError, TypeError, ValueError):
            continue
        fail(f"{label}: candidate was accepted")


def metrics_entry(data: dict[str, object]) -> dict[str, object]:
    matches = [
        entry for entry in data["operation"]
        if entry["name"] == "DeleteBucketMetricsConfiguration"
    ]
    if len(matches) != 1:
        fail("DeleteBucketMetricsConfiguration is not unique")
    return matches[0]


def verify_metrics_registry(data: dict[str, object]) -> None:
    entry = metrics_entry(data)
    expected = {
        "public_name": "Delete_Metrics_Configuration",
        "decision_status": "reviewed",
        "human_decisions_resolved": True,
        "qualification": "delete_bucket_metrics",
        "codec": "empty_response",
        "certainty": DELETE_METRICS_CERTAINTY,
        "reconciliation": DELETE_METRICS_RECONCILIATION,
        "coverage": {
            "backend": "missing",
            "client": "covered",
            "server": "missing",
            "corpus": "covered",
        },
        "ada_symbols": [
            "Prepare_Delete_Bucket_Metrics_Configuration",
            "Execute_Delete_Bucket_Metrics_Configuration",
            "Delete_Bucket_Metrics_Operation",
            "Delete_Metrics_Configuration",
            "Finish",
        ],
    }
    for key, value in expected.items():
        if entry.get(key) != value:
            fail(f"DeleteBucketMetricsConfiguration changed: {key}")
    if "removes the selected bucket metrics" not in entry["absence"]:
        fail("DeleteBucketMetricsConfiguration semantics changed")
    if "exact HTTP 204" not in entry["exclusions"][2]:
        fail("DeleteBucketMetricsConfiguration success changed")
    if "previously present" not in entry["exclusions"][3]:
        fail("DeleteBucketMetricsConfiguration presence changed")
    if "does not establish causation" not in entry["exclusions"][4]:
        fail("DeleteBucketMetricsConfiguration reconcile changed")
    if data["qualification"].get(
        "delete_bucket_metrics"
    ) != DELETE_METRICS_LANE:
        fail("DeleteBucketMetricsConfiguration lane changed")


def verify_metrics_negatives(data: dict[str, object]) -> None:
    mutations = (
        ("missing public name", "public_name", None),
        ("wrong public name", "public_name", "Delete_Analytics_Configuration"),
        (
            "broadened success",
            "certainty",
            DELETE_METRICS_CERTAINTY.replace(
                "validated 204", "validated 200 or 204"
            ),
        ),
        (
            "causal reconciliation",
            "reconciliation",
            "Get_Metrics_Configuration proves deletion",
        ),
        ("cross-operation lane", "qualification", "delete_bucket_inventory"),
    )
    for label, key, value in mutations:
        candidate = copy.deepcopy(data)
        entry = metrics_entry(candidate)
        if value is None:
            del entry[key]
        else:
            entry[key] = value
        if candidate == data:
            fail(f"{label}: candidate did not change")
        try:
            verify_metrics_registry(candidate)
        except (KeyError, TypeError, ValueError):
            continue
        fail(f"{label}: candidate was accepted")


def ownership_controls_entry(data: dict[str, object]) -> dict[str, object]:
    matches = [
        entry for entry in data["operation"]
        if entry["name"] == "DeleteBucketOwnershipControls"
    ]
    if len(matches) != 1:
        fail("DeleteBucketOwnershipControls is not unique")
    return matches[0]


def verify_ownership_controls_registry(data: dict[str, object]) -> None:
    entry = ownership_controls_entry(data)
    expected = {
        "public_name": "Delete_Ownership_Controls",
        "decision_status": "reviewed",
        "human_decisions_resolved": True,
        "qualification": "delete_bucket_ownership_controls",
        "codec": "empty_response",
        "certainty": DELETE_OWNERSHIP_CONTROLS_CERTAINTY,
        "reconciliation": DELETE_OWNERSHIP_CONTROLS_RECONCILIATION,
        "coverage": {
            "backend": "covered",
            "client": "covered",
            "server": "covered",
            "corpus": "covered",
        },
        "ada_symbols": [
            "Prepare_Delete_Bucket_Ownership_Controls",
            "Execute_Delete_Bucket_Ownership_Controls",
            "Delete_Ownership_Controls_Operation",
            "Delete_Ownership_Controls",
            "Finish",
        ],
    }
    for key, value in expected.items():
        if entry.get(key) != value:
            fail(f"DeleteBucketOwnershipControls changed: {key}")
    if "removes the bucket ownership-controls" not in entry["absence"]:
        fail("DeleteBucketOwnershipControls semantics changed")
    if "exact HTTP 204" not in entry["exclusions"][2]:
        fail("DeleteBucketOwnershipControls success changed")
    if "previously present" not in entry["exclusions"][3]:
        fail("DeleteBucketOwnershipControls presence changed")
    if "does not establish causation" not in entry["exclusions"][4]:
        fail("DeleteBucketOwnershipControls reconcile changed")
    if data["qualification"].get(
        "delete_bucket_ownership_controls"
    ) != DELETE_OWNERSHIP_CONTROLS_LANE:
        fail("DeleteBucketOwnershipControls lane changed")


def verify_ownership_controls_negatives(data: dict[str, object]) -> None:
    mutations = (
        ("missing public name", "public_name", None),
        ("wrong public name", "public_name", "Delete_Metrics_Configuration"),
        (
            "broadened success",
            "certainty",
            DELETE_OWNERSHIP_CONTROLS_CERTAINTY.replace(
                "validated 204", "validated 200 or 204"
            ),
        ),
        (
            "causal reconciliation",
            "reconciliation",
            "Get_Ownership_Controls proves deletion",
        ),
        ("cross-operation lane", "qualification", "delete_bucket_metrics"),
    )
    for label, key, value in mutations:
        candidate = copy.deepcopy(data)
        entry = ownership_controls_entry(candidate)
        if value is None:
            del entry[key]
        else:
            entry[key] = value
        if candidate == data:
            fail(f"{label}: candidate did not change")
        try:
            verify_ownership_controls_registry(candidate)
        except (KeyError, TypeError, ValueError):
            continue
        fail(f"{label}: candidate was accepted")


def delete_policy_entry(data: dict[str, object]) -> dict[str, object]:
    matches = [
        entry for entry in data["operation"]
        if entry["name"] == "DeleteBucketPolicy"
    ]
    if len(matches) != 1:
        fail("DeleteBucketPolicy is not unique")
    return matches[0]


def verify_delete_policy_registry(data: dict[str, object]) -> None:
    entry = delete_policy_entry(data)
    expected = {
        "public_name": "Delete_Policy",
        "decision_status": "reviewed",
        "human_decisions_resolved": True,
        "qualification": "delete_bucket_policy",
        "codec": "empty_response",
        "certainty": DELETE_POLICY_CERTAINTY,
        "reconciliation": DELETE_POLICY_RECONCILIATION,
        "coverage": {
            "backend": "covered",
            "client": "covered",
            "server": "covered",
            "corpus": "covered",
        },
        "ada_symbols": [
            "Prepare_Delete_Bucket_Policy",
            "Execute_Delete_Bucket_Policy",
            "Delete_Bucket_Policy_Operation",
            "Delete_Policy",
            "Finish",
        ],
    }
    for key, value in expected.items():
        if entry.get(key) != value:
            fail(f"DeleteBucketPolicy changed: {key}")
    if "removes the bucket policy" not in entry["absence"]:
        fail("DeleteBucketPolicy semantics changed")
    if "exact HTTP 204" not in entry["exclusions"][1]:
        fail("DeleteBucketPolicy success changed")
    if "previously present" not in entry["exclusions"][2]:
        fail("DeleteBucketPolicy presence changed")
    if "does not establish causation" not in entry["exclusions"][3]:
        fail("DeleteBucketPolicy reconcile changed")
    if data["qualification"].get(
        "delete_bucket_policy"
    ) != DELETE_POLICY_LANE:
        fail("DeleteBucketPolicy lane changed")


def verify_delete_policy_negatives(data: dict[str, object]) -> None:
    mutations = (
        ("missing public name", "public_name", None),
        ("wrong public name", "public_name", "Delete_Ownership_Controls"),
        (
            "broadened success",
            "certainty",
            DELETE_POLICY_CERTAINTY.replace(
                "validated 204", "validated 200 or 204"
            ),
        ),
        (
            "causal reconciliation",
            "reconciliation",
            "Get_Policy proves deletion",
        ),
        (
            "cross-operation lane",
            "qualification",
            "delete_bucket_ownership_controls",
        ),
    )
    for label, key, value in mutations:
        candidate = copy.deepcopy(data)
        entry = delete_policy_entry(candidate)
        if value is None:
            del entry[key]
        else:
            entry[key] = value
        if candidate == data:
            fail(f"{label}: candidate did not change")
        try:
            verify_delete_policy_registry(candidate)
        except (KeyError, TypeError, ValueError):
            continue
        fail(f"{label}: candidate was accepted")


def get_policy_entry(data: dict[str, object]) -> dict[str, object]:
    matches = [
        entry for entry in data["operation"]
        if entry["name"] == "GetBucketPolicy"
    ]
    if len(matches) != 1:
        fail("GetBucketPolicy is not unique")
    return matches[0]


def verify_get_policy_registry(data: dict[str, object]) -> None:
    entry = get_policy_entry(data)
    expected = {
        "public_name": "Get_Policy",
        "decision_status": "reviewed",
        "human_decisions_resolved": True,
        "qualification": "get_bucket_policy",
        "codec": "bounded_bytes_and_headers",
        "certainty": "read_only",
        "reconciliation": "not_applicable",
        "coverage": {
            "backend": "covered",
            "client": "covered",
            "server": "covered",
            "corpus": "covered",
        },
        "ada_symbols": [
            "Prepare_Get_Bucket_Policy",
            "Execute_Get_Bucket_Policy",
            "Get_Bucket_Policy_Operation",
            "Get_Policy",
            "Finish",
        ],
    }
    for key, value in expected.items():
        if entry.get(key) != value:
            fail(f"GetBucketPolicy changed: {key}")
    if "exact bounded bucket-policy bytes" not in entry["absence"]:
        fail("GetBucketPolicy success semantics changed")
    if "NoSuchBucketPolicy" not in entry["absence"]:
        fail("GetBucketPolicy absence semantics changed")
    if "exact HTTP 200" not in entry["exclusions"][1]:
        fail("GetBucketPolicy status changed")
    if "distinct from NoSuchBucket" not in entry["exclusions"][2]:
        fail("GetBucketPolicy not-found boundary changed")
    if data["qualification"].get("get_bucket_policy") != GET_POLICY_LANE:
        fail("GetBucketPolicy lane changed")


def verify_get_policy_negatives(data: dict[str, object]) -> None:
    mutations = (
        ("missing public name", "public_name", None),
        ("wrong public name", "public_name", "Get_Policy_Status"),
        ("mutation certainty", "certainty", "outcome_unknown"),
        ("invented reconciliation", "reconciliation", "Get retries itself"),
        ("cross-operation lane", "qualification", "delete_bucket_policy"),
    )
    for label, key, value in mutations:
        candidate = copy.deepcopy(data)
        entry = get_policy_entry(candidate)
        if value is None:
            del entry[key]
        else:
            entry[key] = value
        if candidate == data:
            fail(f"{label}: candidate did not change")
        try:
            verify_get_policy_registry(candidate)
        except (KeyError, TypeError, ValueError):
            continue
        fail(f"{label}: candidate was accepted")


def put_policy_entry(data: dict[str, object]) -> dict[str, object]:
    matches = [
        entry for entry in data["operation"]
        if entry["name"] == "PutBucketPolicy"
    ]
    if len(matches) != 1:
        fail("PutBucketPolicy is not unique")
    return matches[0]


def verify_put_policy_registry(data: dict[str, object]) -> None:
    entry = put_policy_entry(data)
    expected = {
        "public_name": "Set_Policy",
        "decision_status": "reviewed",
        "human_decisions_resolved": True,
        "qualification": "put_bucket_policy",
        "codec": "empty_response",
        "certainty": PUT_POLICY_CERTAINTY,
        "reconciliation": PUT_POLICY_RECONCILIATION,
        "coverage": {
            "backend": "covered",
            "client": "covered",
            "server": "covered",
            "corpus": "covered",
        },
        "ada_symbols": [
            "Prepare_Put_Bucket_Policy",
            "Execute_Put_Bucket_Policy",
            "Put_Bucket_Policy_Operation",
            "Set_Policy",
            "Finish",
        ],
    }
    for key, value in expected.items():
        if entry.get(key) != value:
            fail(f"PutBucketPolicy changed: {key}")
    if "atomically replaces" not in entry["absence"]:
        fail("PutBucketPolicy replacement semantics changed")
    if "exact HTTP 200" not in entry["exclusions"][1]:
        fail("PutBucketPolicy success changed")
    if "Content-MD5" not in entry["exclusions"][2]:
        fail("PutBucketPolicy checksum binding changed")
    if "does not establish causation" not in entry["exclusions"][4]:
        fail("PutBucketPolicy reconcile changed")
    if data["qualification"].get("put_bucket_policy") != PUT_POLICY_LANE:
        fail("PutBucketPolicy lane changed")


def verify_put_policy_negatives(data: dict[str, object]) -> None:
    mutations = (
        ("missing public name", "public_name", None),
        ("wrong public name", "public_name", "Set_Public_Access_Block"),
        (
            "broadened success",
            "certainty",
            PUT_POLICY_CERTAINTY.replace(
                "validated 200", "validated 200 or 204"
            ),
        ),
        ("causal reconciliation", "reconciliation", "Get_Policy proves put"),
        ("cross-operation lane", "qualification", "get_bucket_policy"),
    )
    for label, key, value in mutations:
        candidate = copy.deepcopy(data)
        entry = put_policy_entry(candidate)
        if value is None:
            del entry[key]
        else:
            entry[key] = value
        if candidate == data:
            fail(f"{label}: candidate did not change")
        try:
            verify_put_policy_registry(candidate)
        except (KeyError, TypeError, ValueError):
            continue
        fail(f"{label}: candidate was accepted")


def delete_public_access_block_entry(
    data: dict[str, object],
) -> dict[str, object]:
    matches = [
        entry for entry in data["operation"]
        if entry["name"] == "DeletePublicAccessBlock"
    ]
    if len(matches) != 1:
        fail("DeletePublicAccessBlock is not unique")
    return matches[0]


def verify_delete_public_access_block_registry(
    data: dict[str, object],
) -> None:
    entry = delete_public_access_block_entry(data)
    expected = {
        "public_name": "Delete_Public_Access_Block",
        "decision_status": "reviewed",
        "human_decisions_resolved": True,
        "qualification": "delete_public_access_block",
        "codec": "empty_response",
        "certainty": DELETE_PUBLIC_ACCESS_BLOCK_CERTAINTY,
        "reconciliation": DELETE_PUBLIC_ACCESS_BLOCK_RECONCILIATION,
        "coverage": {
            "backend": "covered",
            "client": "covered",
            "server": "covered",
            "corpus": "covered",
        },
        "ada_symbols": [
            "Prepare_Delete_Public_Access_Block",
            "Execute_Delete_Public_Access_Block",
            "Delete_Public_Access_Block_Operation",
            "Delete_Public_Access_Block",
            "Finish",
        ],
    }
    for key, value in expected.items():
        if entry.get(key) != value:
            fail(f"DeletePublicAccessBlock changed: {key}")
    if "removes the bucket public-access-block" not in entry["absence"]:
        fail("DeletePublicAccessBlock semantics changed")
    if "exact HTTP 204" not in entry["exclusions"][2]:
        fail("DeletePublicAccessBlock success changed")
    if "previously present" not in entry["exclusions"][3]:
        fail("DeletePublicAccessBlock presence changed")
    if "does not establish causation" not in entry["exclusions"][4]:
        fail("DeletePublicAccessBlock reconcile changed")
    if data["qualification"].get(
        "delete_public_access_block"
    ) != DELETE_PUBLIC_ACCESS_BLOCK_LANE:
        fail("DeletePublicAccessBlock lane changed")


def verify_delete_public_access_block_negatives(
    data: dict[str, object],
) -> None:
    mutations = (
        ("missing public name", "public_name", None),
        ("wrong public name", "public_name", "Delete_Policy"),
        (
            "broadened success",
            "certainty",
            DELETE_PUBLIC_ACCESS_BLOCK_CERTAINTY.replace(
                "validated 204", "validated 200 or 204"
            ),
        ),
        (
            "causal reconciliation",
            "reconciliation",
            "Get_Public_Access_Block proves deletion",
        ),
        ("cross-operation lane", "qualification", "delete_bucket_policy"),
    )
    for label, key, value in mutations:
        candidate = copy.deepcopy(data)
        entry = delete_public_access_block_entry(candidate)
        if value is None:
            del entry[key]
        else:
            entry[key] = value
        if candidate == data:
            fail(f"{label}: candidate did not change")
        try:
            verify_delete_public_access_block_registry(candidate)
        except (KeyError, TypeError, ValueError):
            continue
        fail(f"{label}: candidate was accepted")


def get_public_access_block_entry(
    data: dict[str, object],
) -> dict[str, object]:
    matches = [
        entry for entry in data["operation"]
        if entry["name"] == "GetPublicAccessBlock"
    ]
    if len(matches) != 1:
        fail("GetPublicAccessBlock is not unique")
    return matches[0]


def verify_get_public_access_block_registry(
    data: dict[str, object],
) -> None:
    entry = get_public_access_block_entry(data)
    expected = {
        "public_name": "Get_Public_Access_Block",
        "decision_status": "reviewed",
        "human_decisions_resolved": True,
        "qualification": "get_public_access_block",
        "codec": "rest_xml_and_headers",
        "certainty": "read_only",
        "reconciliation": "not_applicable",
        "coverage": {
            "backend": "covered",
            "client": "covered",
            "server": "covered",
            "corpus": "covered",
        },
        "ada_symbols": [
            "Prepare_Get_Public_Access_Block",
            "Execute_Get_Public_Access_Block",
            "Get_Public_Access_Block_Operation",
            "Get_Public_Access_Block",
            "Finish",
        ],
    }
    for key, value in expected.items():
        if entry.get(key) != value:
            fail(f"GetPublicAccessBlock changed: {key}")
    if "independent member presence" not in entry["absence"]:
        fail("GetPublicAccessBlock presence semantics changed")
    if "NoSuchPublicAccessBlockConfiguration" not in entry["absence"]:
        fail("GetPublicAccessBlock absence semantics changed")
    if "exact HTTP 200" not in entry["exclusions"][2]:
        fail("GetPublicAccessBlock success changed")
    if "distinct from NoSuchBucket" not in entry["exclusions"][3]:
        fail("GetPublicAccessBlock not-found boundary changed")
    if data["qualification"].get(
        "get_public_access_block"
    ) != GET_PUBLIC_ACCESS_BLOCK_LANE:
        fail("GetPublicAccessBlock lane changed")


def verify_get_public_access_block_negatives(
    data: dict[str, object],
) -> None:
    mutations = (
        ("missing public name", "public_name", None),
        ("wrong public name", "public_name", "Get_Policy"),
        ("mutation certainty", "certainty", "outcome_unknown"),
        ("invented reconciliation", "reconciliation", "Get retries itself"),
        ("cross-operation lane", "qualification", "delete_public_access_block"),
    )
    for label, key, value in mutations:
        candidate = copy.deepcopy(data)
        entry = get_public_access_block_entry(candidate)
        if value is None:
            del entry[key]
        else:
            entry[key] = value
        if candidate == data:
            fail(f"{label}: candidate did not change")
        try:
            verify_get_public_access_block_registry(candidate)
        except (KeyError, TypeError, ValueError):
            continue
        fail(f"{label}: candidate was accepted")


def put_public_access_block_entry(
    data: dict[str, object],
) -> dict[str, object]:
    matches = [
        entry for entry in data["operation"]
        if entry["name"] == "PutPublicAccessBlock"
    ]
    if len(matches) != 1:
        fail("PutPublicAccessBlock is not unique")
    return matches[0]


def verify_put_public_access_block_registry(
    data: dict[str, object],
) -> None:
    entry = put_public_access_block_entry(data)
    expected = {
        "public_name": "Set_Public_Access_Block",
        "decision_status": "reviewed",
        "human_decisions_resolved": True,
        "qualification": "put_public_access_block",
        "codec": "empty_response",
        "certainty": PUT_PUBLIC_ACCESS_BLOCK_CERTAINTY,
        "reconciliation": PUT_PUBLIC_ACCESS_BLOCK_RECONCILIATION,
        "coverage": {
            "backend": "covered",
            "client": "covered",
            "server": "covered",
            "corpus": "covered",
        },
        "ada_symbols": [
            "Prepare_Put_Public_Access_Block",
            "Execute_Put_Public_Access_Block",
            "Put_Public_Access_Block_Operation",
            "Set_Public_Access_Block",
            "Finish",
        ],
    }
    for key, value in expected.items():
        if entry.get(key) != value:
            fail(f"PutPublicAccessBlock changed: {key}")
    if "atomically replaces" not in entry["absence"]:
        fail("PutPublicAccessBlock replacement semantics changed")
    if "exact HTTP 200" not in entry["exclusions"][2]:
        fail("PutPublicAccessBlock success changed")
    if "Content-MD5" not in entry["exclusions"][3]:
        fail("PutPublicAccessBlock checksum binding changed")
    if "does not establish causation" not in entry["exclusions"][4]:
        fail("PutPublicAccessBlock reconcile changed")
    if data["qualification"].get(
        "put_public_access_block"
    ) != PUT_PUBLIC_ACCESS_BLOCK_LANE:
        fail("PutPublicAccessBlock lane changed")


def verify_put_public_access_block_negatives(
    data: dict[str, object],
) -> None:
    mutations = (
        ("missing public name", "public_name", None),
        ("wrong public name", "public_name", "Set_Policy"),
        (
            "broadened success",
            "certainty",
            PUT_PUBLIC_ACCESS_BLOCK_CERTAINTY.replace(
                "validated 200", "validated 200 or 204"
            ),
        ),
        (
            "causal reconciliation",
            "reconciliation",
            "Get_Public_Access_Block proves replacement",
        ),
        ("cross-operation lane", "qualification", "get_public_access_block"),
    )
    for label, key, value in mutations:
        candidate = copy.deepcopy(data)
        entry = put_public_access_block_entry(candidate)
        if value is None:
            del entry[key]
        else:
            entry[key] = value
        if candidate == data:
            fail(f"{label}: candidate did not change")
        try:
            verify_put_public_access_block_registry(candidate)
        except (KeyError, TypeError, ValueError):
            continue
        fail(f"{label}: candidate was accepted")


def read_tsv(path: Path, header: list[str]) -> list[dict[str, str]]:
    if b"\r" in path.read_bytes():
        fail(f"{path}: CR characters are not canonical")
    with path.open("r", encoding="utf-8", newline="") as stream:
        reader = csv.DictReader(stream, delimiter="\t")
        if reader.fieldnames != header:
            fail(f"{path}: header mismatch")
        rows = list(reader)
    if not rows:
        fail(f"{path}: no rows")
    for number, row in enumerate(rows, 2):
        if None in row or any(value == "" for value in row.values()):
            fail(f"{path}:{number}: empty or surplus field")
    return rows


def comma_values(value: str) -> list[str]:
    values = value.split(",")
    if any(item == "" or item != item.strip() for item in values):
        fail(f"noncanonical comma list: {value!r}")
    if len(values) != len(set(values)):
        fail(f"duplicate comma-list value: {value!r}")
    return values


def function_body(model: str, function: str) -> str:
    match = re.search(rf"   function {re.escape(function)}(?=\s*\()", model)
    if match is None:
        fail(f"generated model has no {function}")
    tail = model[match.end():]
    marker = f"end {function};"
    if marker not in tail:
        fail(f"generated model has no end for {function}")
    return tail.split(marker, 1)[0]


def operation_scalar(model: str, function: str, enum_stem: str) -> str:
    match = re.search(
        rf"when {re.escape(enum_stem)}_Operation =>\s+return\s+([^;]+);",
        function_body(model, function),
    )
    if match is None:
        fail(f"generated model lacks {function} for {enum_stem}")
    return match.group(1).strip().strip('"')


def member_values(model: str, function: str, shape: int) -> list[str]:
    block = re.search(
        rf"when {shape} =>\s+case Member is(?P<body>.*?)\s+end case;",
        function_body(model, function), re.DOTALL,
    )
    if block is None:
        fail(f"generated model lacks {function} shape {shape}")
    if function == "Member_Name":
        pattern = r'when\s+(\d+)\s+=>\s+return\s+"([^"]+)";'
    elif function == "Member_Required":
        pattern = r"when\s+(\d+)\s+=>\s+return\s+(True|False);"
    else:
        pattern = r"when\s+(\d+)\s+=>\s+return\s+([A-Za-z_]+);"
    pairs = re.findall(pattern, block.group("body"))
    if [int(number) for number, _ in pairs] != list(range(1, len(pairs) + 1)):
        fail(f"shape {shape} {function} ordinals are not contiguous")
    return [value for _, value in pairs]


def member_count(model: str, shape: int) -> int:
    match = re.search(
        rf"when\s+{shape}\s+=>\s+return\s+(\d+);",
        function_body(model, "Member_Count"),
    )
    if match is None:
        fail(f"generated model lacks member count for shape {shape}")
    return int(match.group(1))


def main() -> int:
    registry = tomllib.loads(REGISTRY.read_text(encoding="utf-8"))
    verify_delete_encryption_registry(registry)
    verify_delete_encryption_negatives(registry)
    verify_delete_lifecycle_registry(registry)
    verify_delete_lifecycle_negatives(registry)
    verify_delete_replication_registry(registry)
    verify_delete_replication_negatives(registry)
    verify_delete_website_registry(registry)
    verify_delete_website_negatives(registry)
    verify_delete_analytics_registry(registry)
    verify_delete_analytics_negatives(registry)
    verify_intelligent_tiering_registry(registry)
    verify_intelligent_tiering_negatives(registry)
    verify_inventory_registry(registry)
    verify_inventory_negatives(registry)
    verify_metadata_registry(registry)
    verify_metadata_negatives(registry)
    verify_metadata_table_registry(registry)
    verify_metadata_table_negatives(registry)
    verify_metrics_registry(registry)
    verify_metrics_negatives(registry)
    verify_ownership_controls_registry(registry)
    verify_ownership_controls_negatives(registry)
    verify_delete_policy_registry(registry)
    verify_delete_policy_negatives(registry)
    verify_get_policy_registry(registry)
    verify_get_policy_negatives(registry)
    verify_put_policy_registry(registry)
    verify_put_policy_negatives(registry)
    verify_delete_public_access_block_registry(registry)
    verify_delete_public_access_block_negatives(registry)
    verify_get_public_access_block_registry(registry)
    verify_get_public_access_block_negatives(registry)
    verify_put_public_access_block_registry(registry)
    verify_put_public_access_block_negatives(registry)
    lock = LOCK.read_text(encoding="utf-8")
    if f'revision = "{EXPECTED_REVISION}"' not in lock:
        fail("pinned botocore revision changed")
    if f'service_model_sha256 = "{EXPECTED_SHA256}"' not in lock:
        fail("pinned botocore service hash changed")

    model = MODEL.read_text(encoding="utf-8")
    operations = read_tsv(CORPUS / "operations.tsv", OP_HEADER)
    members = read_tsv(CORPUS / "members.tsv", MEMBER_HEADER)
    vectors = read_tsv(CORPUS / "vectors.tsv", VECTOR_HEADER)
    if [row["operation"] for row in operations] != [item[0] for item in EXPECTED]:
        fail("operation inventory or order changed")

    texts = {
        "low-level specification": LOW_SPEC.read_text(encoding="utf-8"),
        "low-level body": LOW_BODY.read_text(encoding="utf-8"),
        "high-level specification": HIGH_SPEC.read_text(encoding="utf-8"),
        "high-level body": HIGH_BODY.read_text(encoding="utf-8"),
    }
    model_spec = MODEL_SPEC.read_text(encoding="utf-8")
    testing = TESTING.read_text(encoding="utf-8")
    socket = SOCKET.read_text(encoding="utf-8")
    qualification = " ".join(
        QUALIFICATION.read_text(encoding="utf-8").split()
    )
    bucket_policy_qualification = " ".join(
        BUCKET_POLICY_QUALIFICATION.read_text(encoding="utf-8").split()
    )
    public_access_block_qualification = " ".join(
        PUBLIC_ACCESS_BLOCK_QUALIFICATION.read_text(
            encoding="utf-8"
        ).split()
    )
    if model_spec.count(
        "@enum Delete_Bucket_Encryption_Operation "
        "Delete bucket encryption"
    ) != 1:
        fail("DeleteBucketEncryption generated documentation changed")
    if model_spec.count(
        "@enum Delete_Bucket_Lifecycle_Operation Delete bucket lifecycle"
    ) != 1:
        fail("DeleteBucketLifecycle generated documentation changed")
    if model_spec.count(
        "@enum Delete_Bucket_Replication_Operation Delete bucket replication"
    ) != 1:
        fail("DeleteBucketReplication generated documentation changed")
    if model_spec.count(
        "@enum Delete_Bucket_Website_Operation Delete bucket website"
    ) != 1:
        fail("DeleteBucketWebsite generated documentation changed")
    if model_spec.count(
        "@enum Delete_Bucket_Analytics_Configuration_Operation "
        "Delete analytics"
    ) != 1:
        fail("DeleteBucketAnalyticsConfiguration documentation changed")
    intelligent_tiering_documentation = (
        "@enum Delete_Bucket_Intelligent_Tiering_Configuration_Operation\n"
        "   --    Delete intelligent-tiering configuration"
    )
    if model_spec.count(intelligent_tiering_documentation) != 1:
        fail("DeleteBucketIntelligentTieringConfiguration docs changed")
    inventory_documentation = (
        "@enum Delete_Bucket_Inventory_Configuration_Operation\n"
        "   --    Delete inventory configuration"
    )
    if model_spec.count(inventory_documentation) != 1:
        fail("DeleteBucketInventoryConfiguration docs changed")
    metadata_documentation = (
        "@enum Delete_Bucket_Metadata_Configuration_Operation\n"
        "   --    Delete metadata configuration"
    )
    if model_spec.count(metadata_documentation) != 1:
        fail("DeleteBucketMetadataConfiguration docs changed")
    metadata_table_documentation = (
        "@enum Delete_Bucket_Metadata_Table_Configuration_Operation\n"
        "   --    Delete metadata-table configuration"
    )
    if model_spec.count(metadata_table_documentation) != 1:
        fail("DeleteBucketMetadataTableConfiguration docs changed")
    metrics_documentation = (
        "@enum Delete_Bucket_Metrics_Configuration_Operation\n"
        "   --    Delete metrics configuration"
    )
    if model_spec.count(metrics_documentation) != 1:
        fail("DeleteBucketMetricsConfiguration docs changed")
    ownership_controls_documentation = (
        "@enum Delete_Bucket_Ownership_Controls_Operation\n"
        "   --    Delete bucket ownership controls"
    )
    if model_spec.count(ownership_controls_documentation) != 1:
        fail("DeleteBucketOwnershipControls docs changed")
    if model_spec.count(
        "@enum Delete_Bucket_Policy_Operation Delete bucket policy"
    ) != 1:
        fail("DeleteBucketPolicy docs changed")
    if model_spec.count(
        "@enum Get_Bucket_Policy_Operation Get bucket policy"
    ) != 1:
        fail("GetBucketPolicy docs changed")
    if model_spec.count(
        "@enum Put_Bucket_Policy_Operation Put bucket policy"
    ) != 1:
        fail("PutBucketPolicy docs changed")
    if model_spec.count(
        "@enum Delete_Public_Access_Block_Operation Delete public access block"
    ) != 1:
        fail("DeletePublicAccessBlock docs changed")
    if model_spec.count(
        "@enum Put_Public_Access_Block_Operation Put public access block"
    ) != 1:
        fail("PutPublicAccessBlock docs changed")
    ordered(
        texts["high-level body"],
        [
            "function Conclusive_Bucket_Encryption_Rejection",
            "function Normalize_Delete_Bucket_Encryption_Response",
            "Bucket_Encryption_Mutation_Completed",
            "Bucket_Encryption_Mutation_Definitely_Not_Applied",
            "function Normalize_Delete_Bucket_Encryption_Failure",
            "procedure Start_Delete_Bucket_Encryption",
            "DeleteBucketEncryption restart changed a retained owner",
            "procedure Finish",
        ],
        "DeleteBucketEncryption provider",
    )
    ordered(
        testing,
        [
            "procedure Check_Bucket_Encryption_Result_Corpus",
            "Check_Delete",
            '(204, "", Bucket_Encryption_Mutation_Completed, No_Failure)',
            '(409, "OperationAborted",',
            "Bucket_Encryption_Mutation_Outcome_Unknown",
            "for Admission in",
            "Normalize_Delete_Bucket_Encryption_Failure",
        ],
        "DeleteBucketEncryption certainty corpus",
    )
    ordered(
        socket,
        [
            '"DeleteBucketEncryption"',
            "typed DeleteBucketEncryption response mismatch",
            "DeleteBucketEncryption accepted an ownership-controls",
            "composed DeleteBucketEncryption mismatch",
            "restarted DeleteBucketEncryption mismatch",
        ],
        "DeleteBucketEncryption socket evidence",
    )
    ordered(
        qualification,
        [
            "resets bucket default encryption to SSE-S3",
            "does not create an absent configuration state",
            "covered / covered / covered / covered",
            "removed exactly the one candidate-owned",
            "added none",
            "delete_bucket_encryption",
        ],
        "DeleteBucketEncryption qualification prose",
    )
    ordered(
        texts["high-level body"],
        [
            "function Conclusive_Bucket_Lifecycle_Rejection",
            "function Normalize_Delete_Bucket_Lifecycle_Response",
            "Bucket_Lifecycle_Mutation_Completed",
            "Bucket_Lifecycle_Mutation_Definitely_Not_Applied",
            "function Normalize_Delete_Bucket_Lifecycle_Failure",
            "procedure Start_Delete_Bucket_Lifecycle",
            "DeleteBucketLifecycle restart changed a retained owner",
            "procedure Finish",
        ],
        "DeleteBucketLifecycle provider",
    )
    ordered(
        testing,
        [
            "procedure Check_Delete_Bucket_Lifecycle_Certainty_Corpus",
            "Check_Response",
            "Bucket_Lifecycle_Mutation_Completed, No_Failure",
            '(409, "OperationAborted",',
            "Bucket_Lifecycle_Mutation_Outcome_Unknown",
            "for Admission in",
            "Normalize_Delete_Bucket_Lifecycle_Failure",
        ],
        "DeleteBucketLifecycle certainty corpus",
    )
    ordered(
        socket,
        [
            '"DeleteBucketLifecycle"',
            "typed DeleteBucketLifecycle response mismatch",
            "DeleteBucketLifecycle accepted an encryption request",
            "composed DeleteBucketLifecycle mismatch",
            "restarted DeleteBucketLifecycle mismatch",
        ],
        "DeleteBucketLifecycle socket evidence",
    )
    ordered(
        qualification,
        [
            "removes every rule from the bucket lifecycle configuration",
            "NoSuchLifecycleConfiguration",
            "covered / covered / covered / covered",
            "Delete_Bucket_Lifecycle_Operation",
            "added none",
            "delete_bucket_lifecycle",
        ],
        "DeleteBucketLifecycle qualification prose",
    )
    ordered(
        texts["high-level body"],
        [
            "function Conclusive_Bucket_Replication_Rejection",
            "function Normalize_Delete_Bucket_Replication_Response",
            "Bucket_Replication_Mutation_Completed",
            "Bucket_Replication_Mutation_Definitely_Not_Applied",
            "function Normalize_Delete_Bucket_Replication_Failure",
            "procedure Start_Delete_Bucket_Replication",
            "DeleteBucketReplication restart changed a retained owner",
            "procedure Finish",
        ],
        "DeleteBucketReplication provider",
    )
    ordered(
        testing,
        [
            "procedure Check_Delete_Bucket_Replication_Certainty_Corpus",
            "Check_Response",
            "Bucket_Replication_Mutation_Completed, No_Failure",
            '(409, "OperationAborted",',
            "Bucket_Replication_Mutation_Outcome_Unknown",
            "for Admission in",
            "Normalize_Delete_Bucket_Replication_Failure",
        ],
        "DeleteBucketReplication certainty corpus",
    )
    ordered(
        socket,
        [
            '"DeleteBucketReplication"',
            "typed DeleteBucketReplication response mismatch",
            "DeleteBucketReplication accepted a website request",
            "composed DeleteBucketReplication mismatch",
            "restarted DeleteBucketReplication mismatch",
        ],
        "DeleteBucketReplication socket evidence",
    )
    ordered(
        qualification,
        [
            "removes the bucket replication configuration",
            "ReplicationConfigurationNotFoundError",
            "missing / covered / missing / covered",
            "Delete_Bucket_Replication_Operation",
            "added none",
            "delete_bucket_replication",
        ],
        "DeleteBucketReplication qualification prose",
    )
    ordered(
        texts["high-level body"],
        [
            "function Conclusive_Bucket_Website_Rejection",
            "function Normalize_Delete_Bucket_Website_Response",
            "Bucket_Website_Mutation_Completed",
            "Bucket_Website_Mutation_Definitely_Not_Applied",
            "function Normalize_Delete_Bucket_Website_Failure",
            "procedure Start_Delete_Bucket_Website",
            "DeleteBucketWebsite restart changed a retained owner",
            "procedure Finish",
        ],
        "DeleteBucketWebsite provider",
    )
    ordered(
        testing,
        [
            "procedure Check_Delete_Bucket_Website_Certainty_Corpus",
            "Check_Response",
            "Bucket_Website_Mutation_Completed, No_Failure",
            '(409, "OperationAborted",',
            "Bucket_Website_Mutation_Outcome_Unknown",
            "for Admission in",
            "Normalize_Delete_Bucket_Website_Failure",
        ],
        "DeleteBucketWebsite certainty corpus",
    )
    ordered(
        socket,
        [
            '"DeleteBucketWebsite"',
            "typed DeleteBucketWebsite response mismatch",
            "DeleteBucketWebsite accepted a lifecycle request",
            "composed DeleteBucketWebsite mismatch",
            "restarted DeleteBucketWebsite mismatch",
        ],
        "DeleteBucketWebsite socket evidence",
    )
    ordered(
        qualification,
        [
            "removes the bucket website configuration",
            "NoSuchWebsiteConfiguration",
            "previously present",
            "missing / covered / missing / covered",
            "Delete_Bucket_Website_Operation",
            "added none",
            "delete_bucket_website",
        ],
        "DeleteBucketWebsite qualification prose",
    )
    ordered(
        texts["high-level body"],
        [
            "function Normalize_Delete_Bucket_Analytics_Response",
            "Bucket_Analytics_Configuration_Mutation_Completed",
            "Bucket_Analytics_Configuration_Mutation_Definitely_Not_Applied",
            "function Normalize_Delete_Bucket_Analytics_Failure",
            "procedure Start_Delete_Bucket_Analytics",
            "DeleteBucketAnalyticsConfiguration restart changed a",
            "procedure Finish",
        ],
        "DeleteBucketAnalyticsConfiguration provider",
    )
    ordered(
        testing,
        [
            "procedure Check_Delete_Bucket_Analytics_Certainty_Corpus",
            "Check_Response",
            '(204, "", Completed, No_Failure)',
            '(409, "OperationAborted",',
            "for Admission in",
            "Normalize_Delete_Bucket_Analytics_Failure",
        ],
        "DeleteBucketAnalyticsConfiguration certainty corpus",
    )
    ordered(
        socket,
        [
            '"DeleteBucketAnalyticsConfiguration"',
            "typed DeleteBucketAnalyticsConfiguration",
            "DeleteBucketAnalyticsConfiguration accepted ",
            "an intelligent-tiering ",
            "composed DeleteBucketAnalyticsConfiguration",
            "restarted DeleteBucketAnalyticsConfiguration",
        ],
        "DeleteBucketAnalyticsConfiguration socket evidence",
    )
    ordered(
        qualification,
        [
            "removes the selected analytics configuration",
            "NoSuchConfiguration",
            "prior presence",
            "missing / covered / missing / covered",
            "Delete_Bucket_Analytics_Configuration_Operation",
            "added none",
            "delete_bucket_analytics",
        ],
        "DeleteBucketAnalyticsConfiguration qualification prose",
    )
    ordered(
        texts["high-level body"],
        [
            "function Normalize_Delete_Bucket_Tiering_Response",
            "Bucket_Tiering_Configuration_Mutation_Completed",
            "Bucket_Tiering_Configuration_Mutation_Definitely_Not_Applied",
            "function Normalize_Delete_Bucket_Tiering_Failure",
            "procedure Start_Delete_Bucket_Tiering",
            "DeleteBucketIntelligentTieringConfiguration restart changed a",
            "procedure Finish",
        ],
        "DeleteBucketIntelligentTieringConfiguration provider",
    )
    ordered(
        testing,
        [
            "procedure Check_Delete_Bucket_Intelligent_Tiering_Certainty_Corpus",
            "Bucket_Tiering_Configuration_Mutation_Completed",
            "Check_Response",
            '(409, "OperationAborted",',
            "for Admission in",
            "Normalize_Delete_Bucket_Tiering_Failure",
        ],
        "DeleteBucketIntelligentTieringConfiguration certainty corpus",
    )
    ordered(
        socket,
        [
            '"DeleteBucketIntelligentTieringConfiguration"',
            "typed DeleteBucketIntelligentTieringConfiguration",
            "DeleteBucketIntelligentTieringConfiguration accepted ",
            "an analytics ",
            "composed DeleteBucketIntelligentTieringConfiguration",
            "restarted DeleteBucketIntelligentTieringConfiguration",
            "duplicate ",
            "an empty ",
            "bounded DeleteBucketIntelligentTieringConfiguration",
        ],
        "DeleteBucketIntelligentTieringConfiguration socket evidence",
    )
    ordered(
        qualification,
        [
            "removes the selected intelligent-tiering configuration",
            "NoSuchConfiguration",
            "prior presence",
            "missing / covered / missing / covered",
            "Delete_Bucket_Intelligent_Tiering_Configuration_Operation",
            "added none",
            "delete_bucket_intelligent_tiering",
        ],
        "DeleteBucketIntelligentTieringConfiguration qualification prose",
    )
    ordered(
        texts["high-level body"],
        [
            (
                "function Normalize_Delete_Bucket_Inventory_Configuration_"
                "Response"
            ),
            "Bucket_Inventory_Configuration_Mutation_Completed",
            "Bucket_Inventory_Configuration_Mutation_Definitely_Not_Applied",
            "function Normalize_Delete_Bucket_Inventory_Configuration_Failure",
            "procedure Start_Delete_Bucket_Inventory_Configuration",
            "DeleteBucketInventoryConfiguration restart changed a",
            "procedure Finish",
        ],
        "DeleteBucketInventoryConfiguration provider",
    )
    ordered(
        testing,
        [
            (
                "procedure Check_Delete_Bucket_Inventory_Configuration_"
                "Certainty_Corpus"
            ),
            "Bucket_Inventory_Configuration_Mutation_Completed",
            "Check_Response",
            '(409, "OperationAborted",',
            "for Admission in",
            "Normalize_Delete_Bucket_Inventory_Configuration_Failure",
        ],
        "DeleteBucketInventoryConfiguration certainty corpus",
    )
    ordered(
        socket,
        [
            '"DeleteBucketInventoryConfiguration"',
            "typed DeleteBucketInventoryConfiguration response",
            "DeleteBucketInventoryConfiguration accepted an analytics ",
            "composed DeleteBucketInventoryConfiguration mismatch",
            "restarted DeleteBucketInventoryConfiguration mismatch",
            "accepted duplicate ",
            "accepted an empty ",
            "bounded DeleteBucketInventoryConfiguration response",
        ],
        "DeleteBucketInventoryConfiguration socket evidence",
    )
    ordered(
        qualification,
        [
            "removes the selected inventory configuration",
            "NoSuchConfiguration",
            "prior presence",
            "missing / covered / missing / covered",
            "Delete_Bucket_Inventory_Configuration_Operation",
            "added none",
            "delete_bucket_inventory",
        ],
        "DeleteBucketInventoryConfiguration qualification prose",
    )
    ordered(
        texts["high-level body"],
        [
            "function Normalize_Delete_Bucket_Metadata_Response",
            "Bucket_Metadata_Configuration_Mutation_Completed",
            "Bucket_Metadata_Configuration_Mutation_Definitely_Not_Applied",
            "function Normalize_Delete_Bucket_Metadata_Failure",
            "procedure Start_Delete_Bucket_Metadata",
            "DeleteBucketMetadataConfiguration restart changed a",
            "procedure Finish",
        ],
        "DeleteBucketMetadataConfiguration provider",
    )
    ordered(
        testing,
        [
            "procedure Check_Delete_Bucket_Metadata_Certainty_Corpus",
            "Bucket_Metadata_Configuration_Mutation_Completed",
            "Check_Response",
            '(409, "OperationAborted",',
            "for Admission in",
            "Normalize_Delete_Bucket_Metadata_Failure",
        ],
        "DeleteBucketMetadataConfiguration certainty corpus",
    )
    ordered(
        socket,
        [
            '"DeleteBucketMetadataConfiguration"',
            "typed DeleteBucketMetadataConfiguration ",
            "DeleteBucketMetadataConfiguration accepted ",
            "a lifecycle ",
            "composed DeleteBucketMetadataConfiguration ",
            "restarted DeleteBucketMetadataConfiguration ",
            "DeleteBucketMetadataConfiguration accepted ",
            '"duplicate " &',
            "DeleteBucketMetadataConfiguration accepted ",
            '"an empty " &',
            "bounded DeleteBucketMetadataConfiguration ",
        ],
        "DeleteBucketMetadataConfiguration socket evidence",
    )
    ordered(
        qualification,
        [
            "removes the bucket metadata configuration",
            "structured rejection",
            "prior presence",
            "missing / covered / missing / covered",
            "Delete_Bucket_Metadata_Configuration_Operation",
            "added none",
            "delete_bucket_metadata",
        ],
        "DeleteBucketMetadataConfiguration qualification prose",
    )
    ordered(
        texts["high-level body"],
        [
            "function Normalize_Delete_Bucket_Metadata_Table_Response",
            "Bucket_Metadata_Table_Mutation_Completed",
            "Bucket_Metadata_Table_Mutation_Definitely_Not_Applied",
            "function Normalize_Delete_Bucket_Metadata_Table_Failure",
            "procedure Start_Delete_Bucket_Metadata_Table",
            "DeleteBucketMetadataTableConfiguration restart changed a",
            "procedure Finish",
        ],
        "DeleteBucketMetadataTableConfiguration provider",
    )
    ordered(
        testing,
        [
            "procedure Check_Delete_Bucket_Metadata_Table_Certainty_Corpus",
            "Bucket_Metadata_Table_Mutation_Completed",
            "Check_Response",
            '(409, "OperationAborted",',
            "for Admission in",
            "Normalize_Delete_Bucket_Metadata_Table_Failure",
        ],
        "DeleteBucketMetadataTableConfiguration certainty corpus",
    )
    ordered(
        socket,
        [
            '"/typed-delete-metadata-table?metadataTable"',
            "typed DeleteBucketMetadataTableConfiguration ",
            "DeleteBucketMetadataTableConfiguration accepted ",
            "a lifecycle ",
            "composed DeleteBucketMetadataTableConfiguration ",
            "restarted DeleteBucketMetadataTableConfiguration ",
            "DeleteBucketMetadataTableConfiguration accepted ",
            '"duplicate " &',
            "DeleteBucketMetadataTableConfiguration accepted ",
            '"an empty " &',
            "bounded DeleteBucketMetadataTableConfiguration ",
        ],
        "DeleteBucketMetadataTableConfiguration socket evidence",
    )
    ordered(
        qualification,
        [
            "removes the bucket metadata-table configuration",
            "structured rejection",
            "prior presence",
            "missing / covered / missing / covered",
            "Delete_Bucket_Metadata_Table_Configuration_Operation",
            "added none",
            "delete_bucket_metadata_table",
        ],
        "DeleteBucketMetadataTableConfiguration qualification prose",
    )
    ordered(
        texts["high-level body"],
        [
            "function Normalize_Delete_Bucket_Metrics_Response",
            "Bucket_Metrics_Configuration_Mutation_Completed",
            "Bucket_Metrics_Configuration_Mutation_Definitely_Not_Applied",
            "function Normalize_Delete_Bucket_Metrics_Failure",
            "procedure Start_Delete_Bucket_Metrics",
            "DeleteBucketMetricsConfiguration restart changed a",
            "procedure Finish",
        ],
        "DeleteBucketMetricsConfiguration provider",
    )
    ordered(
        testing,
        [
            "procedure Check_Delete_Bucket_Metrics_Certainty_Corpus",
            "Bucket_Metrics_Configuration_Mutation_Completed",
            "Check_Response",
            '(409, "OperationAborted",',
            "for Admission in",
            "Normalize_Delete_Bucket_Metrics_Failure",
        ],
        "DeleteBucketMetricsConfiguration certainty corpus",
    )
    ordered(
        socket,
        [
            '"/typed-delete-metrics?id=config%20id&metrics"',
            "typed DeleteBucketMetricsConfiguration ",
            "DeleteBucketMetricsConfiguration accepted ",
            "an intelligent-tiering ",
            "composed DeleteBucketMetricsConfiguration ",
            "restarted DeleteBucketMetricsConfiguration ",
            "DeleteBucketMetricsConfiguration accepted ",
            '"duplicate " &',
            "DeleteBucketMetricsConfiguration accepted ",
            '"an empty " &',
            "bounded DeleteBucketMetricsConfiguration ",
        ],
        "DeleteBucketMetricsConfiguration socket evidence",
    )
    ordered(
        qualification,
        [
            "removes the selected bucket metrics configuration",
            "NoSuchConfiguration",
            "prior presence",
            "missing / covered / missing / covered",
            "Delete_Bucket_Metrics_Configuration_Operation",
            "added none",
            "delete_bucket_metrics",
        ],
        "DeleteBucketMetricsConfiguration qualification prose",
    )
    ordered(
        texts["high-level body"],
        [
            "function Normalize_Delete_Ownership_Controls_Response",
            "Bucket_Ownership_Controls_Mutation_Completed",
            "Bucket_Ownership_Controls_Mutation_Definitely_Not_Applied",
            "function Normalize_Delete_Ownership_Controls_Failure",
            "procedure Start_Delete_Ownership_Controls",
            "DeleteBucketOwnershipControls restart changed a retained owner",
            "procedure Finish",
        ],
        "DeleteBucketOwnershipControls provider",
    )
    ordered(
        testing,
        [
            "procedure Check_Ownership_Controls_Certainty_Corpus",
            "procedure Check_Delete_Response",
            "Bucket_Ownership_Controls_Mutation_Completed",
            '(404, "NoSuchBucket",',
            "for Kind of Failure_Kinds loop",
            "Normalize_Delete_Ownership_Controls_Failure",
        ],
        "DeleteBucketOwnershipControls certainty corpus",
    )
    ordered(
        socket,
        [
            '"/composed-delete-ownership?ownershipControls"',
            '"/restart-delete-ownership?ownershipControls"',
            "DeleteBucketOwnershipControls accepted a public-access",
            "composed DeleteBucketOwnershipControls mismatch",
            "restarted DeleteBucketOwnershipControls mismatch",
        ],
        "DeleteBucketOwnershipControls socket evidence",
    )
    ordered(
        qualification,
        [
            "removes the bucket ownership-controls configuration",
            "OwnershipControlsNotFoundError",
            "prior presence",
            "covered / covered / covered / covered",
            "Delete_Bucket_Ownership_Controls_Operation",
            "added none",
            "delete_bucket_ownership_controls",
        ],
        "DeleteBucketOwnershipControls qualification prose",
    )
    ordered(
        texts["high-level body"],
        [
            "function Normalize_Delete_Bucket_Policy_Response",
            "Bucket_Policy_Mutation_Completed",
            "Bucket_Policy_Mutation_Definitely_Not_Applied",
            "function Normalize_Delete_Bucket_Policy_Failure",
            "procedure Start_Delete_Bucket_Policy",
            "DeleteBucketPolicy restart changed a retained owner",
            "procedure Finish",
        ],
        "DeleteBucketPolicy provider",
    )
    ordered(
        testing,
        [
            "procedure Check_Bucket_Policy_Certainty_Corpus",
            "procedure Check_Delete_Response",
            "Bucket_Policy_Mutation_Completed",
            '(404, "NoSuchBucket",',
            "for Kind of Failure_Kinds loop",
            "Normalize_Delete_Bucket_Policy_Failure",
        ],
        "DeleteBucketPolicy certainty corpus",
    )
    ordered(
        socket,
        [
            "typed DeleteBucketPolicy response mismatch",
            "composed DeleteBucketPolicy first result mismatch",
            "composed DeleteBucketPolicy restart mismatch",
        ],
        "DeleteBucketPolicy socket evidence",
    )
    ordered(
        qualification,
        [
            "removes the bucket policy",
            "NoSuchBucketPolicy",
            "prior presence",
            "covered / covered / covered / covered",
            "Delete_Bucket_Policy_Operation",
            "added none",
            "delete_bucket_policy",
        ],
        "DeleteBucketPolicy family qualification prose",
    )
    ordered(
        bucket_policy_qualification,
        [
            "`DeleteBucketPolicy` registry lane",
            "exact empty-204 completion",
            "observational `Get_Policy` reconciliation",
            "region-scoped warning measurement only",
        ],
        "DeleteBucketPolicy backend and server qualification prose",
    )
    ordered(
        texts["high-level body"],
        [
            "function Normalize_Get_Bucket_Policy_Response",
            'Code in "NoSuchBucket" | "NoSuchBucketPolicy"',
            "function Normalize_Get_Bucket_Policy_Failure",
            "GetBucketPolicy response exceeds the caller-selected limit",
            "procedure Start_Get_Bucket_Policy",
            "GetBucketPolicy restart changed a retained owner",
            "procedure Finish",
        ],
        "GetBucketPolicy provider",
    )
    ordered(
        testing,
        [
            "Normalize_Get_Bucket_Policy_Failure",
            "procedure Check_Get_Bucket_Policy_Result_Corpus",
            "Check_Get_Bucket_Policy_Response (200, \"\", No_Failure)",
            '(404, "NoSuchBucket", Not_Found)',
            '(404, "NoSuchBucketPolicy", Not_Found)',
            "for Admission in",
        ],
        "GetBucketPolicy certainty corpus",
    )
    ordered(
        socket,
        [
            "GetBucketPolicy accepted a prepared ABAC request",
            "GetBucketPolicy socket mismatch",
            "composed GetBucketPolicy first result mismatch",
            "composed GetBucketPolicy restart mismatch",
        ],
        "GetBucketPolicy socket evidence",
    )
    ordered(
        bucket_policy_qualification,
        [
            "`GetBucketPolicy` registry lane",
            "exact bounded HTTP-200 policy read",
            "`NoSuchBucketPolicy` as absence",
            "The bytes remain opaque",
            "region-scoped warning measurement only",
        ],
        "GetBucketPolicy backend and server qualification prose",
    )
    ordered(
        texts["high-level body"],
        [
            "function Normalize_Put_Bucket_Policy_Response",
            "Bucket_Policy_Mutation_Completed",
            "Bucket_Policy_Mutation_Definitely_Not_Applied",
            "function Normalize_Put_Bucket_Policy_Failure",
            "procedure Start_Put_Bucket_Policy",
            "PutBucketPolicy restart changed a retained owner",
            "procedure Finish",
        ],
        "PutBucketPolicy provider",
    )
    ordered(
        testing,
        [
            "procedure Check_Bucket_Policy_Certainty_Corpus",
            "procedure Check_Put_Response",
            "PutBucketPolicy response normalization mismatch",
            "Bucket_Policy_Mutation_Definitely_Not_Applied",
            "Bucket_Policy_Mutation_Outcome_Unknown",
            "Normalize_Put_Bucket_Policy_Failure",
        ],
        "PutBucketPolicy certainty corpus",
    )
    ordered(
        socket,
        [
            "PutBucketPolicy accepted a prepared ABAC request",
            "typed PutBucketPolicy response mismatch",
            "composed PutBucketPolicy first result mismatch",
            "composed PutBucketPolicy restart mismatch",
        ],
        "PutBucketPolicy socket evidence",
    )
    ordered(
        bucket_policy_qualification,
        [
            "`PutBucketPolicy` registry lane",
            "exact HTTP-200 completion",
            "Content-MD5",
            "unknown outcome after possible admission",
            "noncausal",
            "region-scoped warning measurement only",
        ],
        "PutBucketPolicy backend and server qualification prose",
    )
    ordered(
        texts["high-level body"],
        [
            "function Conclusive_Public_Access_Block_Rejection",
            "function Normalize_Delete_Public_Access_Block_Response",
            "Public_Access_Block_Mutation_Completed",
            "Public_Access_Block_Mutation_Definitely_Not_Applied",
            "function Normalize_Delete_Public_Access_Block_Failure",
            "procedure Start_Delete_Public_Access_Block",
            "DeletePublicAccessBlock restart changed a retained owner",
            "procedure Finish",
        ],
        "DeletePublicAccessBlock provider",
    )
    ordered(
        testing,
        [
            "procedure Check_Public_Access_Block_Certainty_Corpus",
            "procedure Check_Delete",
            "Public_Access_Block_Mutation_Completed, No_Failure",
            '(404, "NoSuchBucket",',
            "Public_Access_Block_Mutation_Definitely_Not_Applied",
            "for Admission in",
            "Normalize_Delete_Public_Access_Block_Failure",
        ],
        "DeletePublicAccessBlock certainty corpus",
    )
    ordered(
        socket,
        [
            '"DeletePublicAccessBlock"',
            "composed DeletePublicAccessBlock result mismatch",
            "restarted DeletePublicAccessBlock result mismatch",
            "DeletePublicAccessBlock accepted a policy request",
        ],
        "DeletePublicAccessBlock socket evidence",
    )
    ordered(
        qualification,
        [
            "`DeletePublicAccessBlock`",
            "covered / covered / covered / covered",
        ],
        "DeletePublicAccessBlock family qualification prose",
    )
    ordered(
        public_access_block_qualification,
        [
            "complete empty 204 response",
            "possibly admitted exchange",
            "`Get_Public_Access_Block`",
            "neither proves the lost deletion caused the state",
            "`delete_public_access_block`, `get_public_access_block`, and",
            "`put_public_access_block` lanes",
            "repository-wide GNATdoc qualification",
        ],
        "DeletePublicAccessBlock backend and server qualification prose",
    )
    ordered(
        texts["high-level body"],
        [
            "function Normalize_Get_Public_Access_Block_Response",
            '"NoSuchBucket" | "NoSuchPublicAccessBlockConfiguration"',
            "function Normalize_Get_Public_Access_Block_Failure",
            "GetPublicAccessBlock response exceeds the caller-selected limit",
            "procedure Start_Get_Public_Access_Block",
            "GetPublicAccessBlock restart changed a retained owner",
            "procedure Finish",
        ],
        "GetPublicAccessBlock provider",
    )
    ordered(
        testing,
        [
            "procedure Check_Public_Access_Block_Certainty_Corpus",
            "procedure Check_Get",
            "GetPublicAccessBlock response normalization mismatch",
            '(404, "NoSuchPublicAccessBlockConfiguration", Not_Found)',
            "Normalize_Get_Public_Access_Block_Failure",
        ],
        "GetPublicAccessBlock certainty corpus",
    )
    ordered(
        socket,
        [
            "GetPublicAccessBlock socket mismatch",
            "GetPublicAccessBlock accepted a prepared ABAC request",
            "composed GetPublicAccessBlock result mismatch",
            "restarted GetPublicAccessBlock result mismatch",
        ],
        "GetPublicAccessBlock socket evidence",
    )
    ordered(
        public_access_block_qualification,
        [
            "reviewed `GetPublicAccessBlock` client contract is read-only",
            "preserves independent presence",
            "`NoSuchPublicAccessBlockConfiguration`",
            "remains distinct from `NoSuchBucket`",
            "`get_public_access_block`, and",
            "`put_public_access_block` lanes",
        ],
        "GetPublicAccessBlock qualification prose",
    )
    ordered(
        texts["high-level body"],
        [
            "function Conclusive_Public_Access_Block_Rejection",
            "function Normalize_Put_Public_Access_Block_Response",
            "Public_Access_Block_Mutation_Completed",
            "function Normalize_Put_Public_Access_Block_Failure",
            "procedure Start_Put_Public_Access_Block",
            "PutPublicAccessBlock restart changed a retained owner",
            "procedure Finish",
        ],
        "PutPublicAccessBlock provider",
    )
    ordered(
        testing,
        [
            "procedure Check_Public_Access_Block_Certainty_Corpus",
            "procedure Check_Put",
            "PutPublicAccessBlock response normalization mismatch",
            "Public_Access_Block_Mutation_Definitely_Not_Applied",
            "Public_Access_Block_Mutation_Outcome_Unknown",
            "Normalize_Put_Public_Access_Block_Failure",
        ],
        "PutPublicAccessBlock certainty corpus",
    )
    ordered(
        socket,
        [
            "composed PutPublicAccessBlock result mismatch",
            "restarted PutPublicAccessBlock result mismatch",
            "PutPublicAccessBlock accepted a prepared ABAC request",
        ],
        "PutPublicAccessBlock socket evidence",
    )
    ordered(
        public_access_block_qualification,
        [
            "reviewed `PutPublicAccessBlock` client contract",
            "empty or whitespace-only response tolerance",
            "never replayed automatically",
            "Content-MD5",
            "neither proves the lost replacement caused that state",
            "`put_public_access_block` lanes",
        ],
        "PutPublicAccessBlock qualification prose",
    )
    expected_member_rows: list[tuple[str, str, str, str, str, str]] = []
    for row, expected in zip(operations, EXPECTED, strict=True):
        operation, enum_stem, shape, uri, has_id, prepare, execute, high = expected
        wanted_members = ["Bucket"] + (["Id"] if has_id else []) + ["ExpectedBucketOwner"]
        wanted_locations = [LOCATION[name] for name in wanted_members]
        wanted_required = ["True"] + (["True"] if has_id else []) + ["False"]
        if operation_scalar(model, "Operation_Name", enum_stem) != operation:
            fail(f"{operation}: generated name changed")
        if operation_scalar(model, "Method", enum_stem) != "Delete_Method":
            fail(f"{operation}: generated method is not DELETE")
        if int(operation_scalar(model, "Input_Shape", enum_stem)) != shape:
            fail(f"{operation}: generated input shape changed")
        if operation_scalar(model, "Output_Shape", enum_stem) != "0":
            fail(f"{operation}: generated output shape changed")
        if operation_scalar(model, "Request_URI", enum_stem) != uri:
            fail(f"{operation}: generated request URI changed")
        if operation_scalar(model, "Response_Code", enum_stem) != "204":
            fail(f"{operation}: generated success code changed")
        if member_count(model, shape) != len(wanted_members):
            fail(f"{operation}: generated member count changed")
        if member_values(model, "Member_Name", shape) != wanted_members:
            fail(f"{operation}: generated member names changed")
        if member_values(model, "Location", shape) != wanted_locations:
            fail(f"{operation}: generated member locations changed")
        if member_values(model, "Member_Required", shape) != wanted_required:
            fail(f"{operation}: generated required flags changed")
        expected_row = [
            operation, str(shape), uri, str(has_id).lower(),
            str(len(wanted_members)), prepare, execute, high,
        ]
        if [row[name] for name in OP_HEADER[:-1]] != expected_row:
            fail(f"{operation}: operation manifest drift")
        for ordinal, (name, location, required) in enumerate(
                zip(wanted_members, wanted_locations, wanted_required, strict=True), 1):
            expected_member_rows.append((
                operation, str(shape), str(ordinal), name,
                {"URI_Location": "uri-label", "Query_Location": "query",
                 "Header_Location": "header"}[location], required.lower(),
            ))
        for label, text in texts.items():
            names = [prepare, execute] if label.startswith("low-level") else [high]
            for name in names:
                if not re.search(rf"\bfunction\s+{re.escape(name)}\b", text):
                    fail(f"{operation}: {name} absent from {label}")

    lifecycle_tokens = {
        "low-level specification": [
            r"\bprocedure\s+Delete_Bucket_Lifecycle\b",
            r"Operation\s*:\s*in\s+out\s+"
            r"Flyology\.HTTP\.Client\.Exchange_Operation",
        ],
        "low-level body": [
            r"\bprocedure\s+Delete_Bucket_Lifecycle\b",
            r"Model\.Delete_Bucket_Lifecycle_Operation",
        ],
        "high-level specification": [
            r"\btype\s+Delete_Bucket_Lifecycle_Operation\b",
            r"\btype\s+Delete_Bucket_Lifecycle_Result\b",
            r"\bprocedure\s+Finish\s*\(\s*Operation\s*:\s*in\s+out\s+"
            r"Delete_Bucket_Lifecycle_Operation",
        ],
        "high-level body": [
            r"\bprocedure\s+Start_Delete_Bucket_Lifecycle\b",
            r"\bfunction\s+Normalize_Delete_Bucket_Lifecycle_Response\b",
            r"Low\.Delete_Bucket_Lifecycle",
        ],
    }
    replication_tokens = {
        "low-level specification": [
            r"\bprocedure\s+Delete_Bucket_Replication\b",
            r"Operation\s*:\s*in\s+out\s+"
            r"Flyology\.HTTP\.Client\.Exchange_Operation",
        ],
        "low-level body": [
            r"\bprocedure\s+Delete_Bucket_Replication\b",
            r"Model\.Delete_Bucket_Replication_Operation",
        ],
        "high-level specification": [
            r"\btype\s+Delete_Bucket_Replication_Operation\b",
            r"\btype\s+Delete_Bucket_Replication_Result\b",
            r"\bprocedure\s+Finish\s*\(\s*Operation\s*:\s*in\s+out\s+"
            r"Delete_Bucket_Replication_Operation",
        ],
        "high-level body": [
            r"\bprocedure\s+Start_Delete_Bucket_Replication\b",
            r"\bfunction\s+Normalize_Delete_Bucket_Replication_Response\b",
            r"Low\.Delete_Bucket_Replication",
        ],
    }
    website_tokens = {
        "low-level specification": [
            r"\bprocedure\s+Delete_Bucket_Website\b",
            r"Operation\s*:\s*in\s+out\s+"
            r"Flyology\.HTTP\.Client\.Exchange_Operation",
        ],
        "low-level body": [
            r"\bprocedure\s+Delete_Bucket_Website\b",
            r"Model\.Delete_Bucket_Website_Operation",
        ],
        "high-level specification": [
            r"\btype\s+Delete_Bucket_Website_Operation\b",
            r"\btype\s+Delete_Bucket_Website_Result\b",
            r"\bprocedure\s+Finish\s*\(\s*Operation\s*:\s*in\s+out\s+"
            r"Delete_Bucket_Website_Operation",
        ],
        "high-level body": [
            r"\bprocedure\s+Start_Delete_Bucket_Website\b",
            r"\bfunction\s+Normalize_Delete_Bucket_Website_Response\b",
            r"Low\.Delete_Bucket_Website",
        ],
    }
    analytics_tokens = {
        "low-level specification": [
            r"\bprocedure\s+Delete_Bucket_Analytics_Configuration\b",
            r"Operation\s*:\s*in\s+out\s+"
            r"Flyology\.HTTP\.Client\.Exchange_Operation",
        ],
        "low-level body": [
            r"\bprocedure\s+Delete_Bucket_Analytics_Configuration\b",
            r"Model\.Delete_Bucket_Analytics_Configuration_Operation",
        ],
        "high-level specification": [
            r"\btype\s+Delete_Bucket_Analytics_Operation\b",
            r"\btype\s+Delete_Bucket_Analytics_Result\b",
            r"\bprocedure\s+Finish\s*\(\s*Operation\s*:\s*in\s+out\s+"
            r"Delete_Bucket_Analytics_Operation",
        ],
        "high-level body": [
            r"\bprocedure\s+Start_Delete_Bucket_Analytics\b",
            r"\bfunction\s+Normalize_Delete_Bucket_Analytics_Response\b",
            r"Low\.Delete_Bucket_Analytics_Configuration",
        ],
    }
    metadata_tokens = {
        "low-level specification": [
            r"\bprocedure\s+Delete_Bucket_Metadata_Configuration\b",
            r"Operation\s*:\s*in\s+out\s+"
            r"Flyology\.HTTP\.Client\.Exchange_Operation",
        ],
        "low-level body": [
            r"\bprocedure\s+Delete_Bucket_Metadata_Configuration\b",
            r"Model\.Delete_Bucket_Metadata_Configuration_Operation",
        ],
        "high-level specification": [
            r"\btype\s+Delete_Bucket_Metadata_Operation\b",
            r"\btype\s+Delete_Bucket_Metadata_Result\b",
            r"\bprocedure\s+Finish\s*\(\s*Operation\s*:\s*in\s+out\s+"
            r"Delete_Bucket_Metadata_Operation",
        ],
        "high-level body": [
            r"\bprocedure\s+Start_Delete_Bucket_Metadata\b",
            r"\bfunction\s+Normalize_Delete_Bucket_Metadata_Response\b",
            r"Low\.Delete_Bucket_Metadata_Configuration",
        ],
    }
    metadata_table_tokens = {
        "low-level specification": [
            r"\bprocedure\s+Delete_Bucket_Metadata_Table_Configuration\b",
            r"Operation\s*:\s*in\s+out\s+"
            r"Flyology\.HTTP\.Client\.Exchange_Operation",
        ],
        "low-level body": [
            r"\bprocedure\s+Delete_Bucket_Metadata_Table_Configuration\b",
            r"Model\.Delete_Bucket_Metadata_Table_Configuration_Operation",
        ],
        "high-level specification": [
            r"\btype\s+Delete_Bucket_Metadata_Table_Operation\b",
            r"\btype\s+Delete_Bucket_Metadata_Table_Result\b",
            r"\bprocedure\s+Finish\s*\(\s*Operation\s*:\s*in\s+out\s+"
            r"Delete_Bucket_Metadata_Table_Operation",
        ],
        "high-level body": [
            r"\bprocedure\s+Start_Delete_Bucket_Metadata_Table\b",
            r"\bfunction\s+Normalize_Delete_Bucket_Metadata_Table_Response\b",
            r"Low\.Delete_Bucket_Metadata_Table_Configuration",
        ],
    }
    metrics_tokens = {
        "low-level specification": [
            r"\bprocedure\s+Delete_Bucket_Metrics_Configuration\b",
            r"Operation\s*:\s*in\s+out\s+"
            r"Flyology\.HTTP\.Client\.Exchange_Operation",
        ],
        "low-level body": [
            r"\bprocedure\s+Delete_Bucket_Metrics_Configuration\b",
            r"Model\.Delete_Bucket_Metrics_Configuration_Operation",
        ],
        "high-level specification": [
            r"\btype\s+Delete_Bucket_Metrics_Operation\b",
            r"\btype\s+Delete_Bucket_Metrics_Result\b",
            r"\bprocedure\s+Finish\s*\(\s*Operation\s*:\s*in\s+out\s+"
            r"Delete_Bucket_Metrics_Operation",
        ],
        "high-level body": [
            r"\bprocedure\s+Start_Delete_Bucket_Metrics\b",
            r"\bfunction\s+Normalize_Delete_Bucket_Metrics_Response\b",
            r"Low\.Delete_Bucket_Metrics_Configuration",
        ],
    }
    intelligent_tiering_tokens = {
        "low-level specification": [
            r"\bprocedure\s+Delete_Bucket_Intelligent_Tiering_Configuration\b",
            r"Operation\s*:\s*in\s+out\s+"
            r"Flyology\.HTTP\.Client\.Exchange_Operation",
        ],
        "low-level body": [
            r"\bprocedure\s+Delete_Bucket_Intelligent_Tiering_Configuration\b",
            r"Model\.Delete_Bucket_Intelligent_Tiering_Configuration_Operation",
        ],
        "high-level specification": [
            r"\btype\s+Delete_Bucket_Tiering_Operation\b",
            r"\btype\s+Delete_Bucket_Tiering_Result\b",
            r"\bprocedure\s+Finish\s*\(\s*Operation\s*:\s*in\s+out\s+"
            r"Delete_Bucket_Tiering_Operation",
        ],
        "high-level body": [
            r"\bprocedure\s+Start_Delete_Bucket_Tiering\b",
            r"\bfunction\s+Normalize_Delete_Bucket_Tiering_Response\b",
            r"Low\.Delete_Bucket_Intelligent_Tiering_Configuration",
        ],
    }
    inventory_tokens = {
        "low-level specification": [
            r"\bprocedure\s+Delete_Bucket_Inventory_Configuration\b",
            r"Operation\s*:\s*in\s+out\s+"
            r"Flyology\.HTTP\.Client\.Exchange_Operation",
        ],
        "low-level body": [
            r"\bprocedure\s+Delete_Bucket_Inventory_Configuration\b",
            r"Model\.Delete_Bucket_Inventory_Configuration_Operation",
        ],
        "high-level specification": [
            r"\btype\s+Delete_Bucket_Inventory_Configuration_Operation\b",
            r"\btype\s+Delete_Bucket_Inventory_Configuration_Result\b",
            r"\bprocedure\s+Finish\s*\(\s*Operation\s*:\s*in\s+out\s+"
            r"Delete_Bucket_Inventory_Configuration_Operation",
        ],
        "high-level body": [
            r"\bprocedure\s+Start_Delete_Bucket_Inventory_Configuration\b",
            r"\bfunction\s+Normalize_Delete_Bucket_Inventory_Configuration_Response\b",
            r"Low\.Delete_Bucket_Inventory_Configuration",
        ],
    }
    for operation, tokens in (
        ("DeleteBucketLifecycle", lifecycle_tokens),
        ("DeleteBucketReplication", replication_tokens),
        ("DeleteBucketWebsite", website_tokens),
        ("DeleteBucketAnalyticsConfiguration", analytics_tokens),
        ("DeleteBucketMetadataConfiguration", metadata_tokens),
        ("DeleteBucketMetadataTableConfiguration", metadata_table_tokens),
        ("DeleteBucketMetricsConfiguration", metrics_tokens),
        ("DeleteBucketIntelligentTieringConfiguration",
         intelligent_tiering_tokens),
        ("DeleteBucketInventoryConfiguration", inventory_tokens),
    ):
        for label, patterns in tokens.items():
            for pattern in patterns:
                if re.search(pattern, texts[label]) is None:
                    fail(f"{operation} composable API absent from {label}")
    for operation, name in (
        ("DeleteBucketLifecycle", "Delete_Lifecycle"),
        ("DeleteBucketReplication", "Delete_Replication"),
        ("DeleteBucketWebsite", "Delete_Website"),
        ("DeleteBucketAnalyticsConfiguration", "Delete_Analytics_Configuration"),
        ("DeleteBucketMetadataConfiguration", "Delete_Metadata_Configuration"),
        ("DeleteBucketMetadataTableConfiguration", "Delete_Metadata_Table_Configuration"),
        ("DeleteBucketMetricsConfiguration", "Delete_Metrics_Configuration"),
        ("DeleteBucketIntelligentTieringConfiguration",
         "Delete_Intelligent_Tiering_Configuration"),
        ("DeleteBucketInventoryConfiguration", "Delete_Inventory_Configuration"),
    ):
        for label in ("high-level specification", "high-level body"):
            if texts[label].count(f"function {name}") != 3:
                fail(f"{operation} function overload count changed in {label}")
            if texts[label].count(f"procedure {name}") != 1:
                fail(f"{operation} reusable overload count changed in {label}")

    if [tuple(row[name] for name in MEMBER_HEADER[:-1]) for row in members] != expected_member_rows:
        fail("member manifest does not exactly match generated input shapes")

    operation_by_name = {row["operation"]: row for row in operations}
    vector_by_id: dict[str, dict[str, str]] = {}
    for vector in vectors:
        vector_id = vector["id"]
        if not re.fullmatch(r"BCF-(?:RQ|RS|TR)-\d{3}", vector_id):
            fail(f"noncanonical vector id: {vector_id}")
        if vector_id in vector_by_id:
            fail(f"duplicate vector id: {vector_id}")
        vector_by_id[vector_id] = vector
        for operation in comma_values(vector["operation_refs"]):
            if operation not in operation_by_name:
                fail(f"{vector_id}: unknown operation {operation}")

    for operation, row in operation_by_name.items():
        for vector_id in comma_values(row["vector_ids"]):
            vector = vector_by_id.get(vector_id)
            if vector is None:
                fail(f"{operation}: unknown vector {vector_id}")
            if operation not in comma_values(vector["operation_refs"]):
                fail(f"{operation}: {vector_id} lacks reciprocal reference")
    for vector_id, vector in vector_by_id.items():
        for operation in comma_values(vector["operation_refs"]):
            if vector_id not in comma_values(operation_by_name[operation]["vector_ids"]):
                fail(f"{vector_id}: {operation} lacks reciprocal reference")
    for member in members:
        for vector_id in comma_values(member["vector_ids"]):
            vector = vector_by_id.get(vector_id)
            if vector is None or member["operation"] not in comma_values(vector["operation_refs"]):
                fail(f"{member['operation']}:{member['member']}: bad vector {vector_id}")

    print(
        "bucket-configuration DELETE preparation: 13 operations, 30 request "
        f"members, no modeled success outputs, {len(vectors)} reciprocal vectors; "
        "pinned model, DeleteBucketEncryption/DeleteBucketLifecycle/"
        "DeleteBucketReplication/DeleteBucketWebsite/"
        "DeleteBucketAnalyticsConfiguration/"
        "DeleteBucketIntelligentTieringConfiguration registry/certainty, "
        "DeleteBucketInventoryConfiguration/"
        "DeleteBucketMetadataConfiguration registry/certainty, and exact "
        "public APIs match, including analytics, metadata, metadata-table, "
        "metrics, ownership-controls, policy, "
        "lifecycle, replication, website, intelligent-tiering, and inventory "
        "composable forms"
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (KeyError, OSError, UnicodeError, ValueError) as exc:
        print(f"bucket-configuration DELETE verification failed: {exc}", file=sys.stderr)
        raise SystemExit(1)
