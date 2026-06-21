output "knowledge_base_id" { value = aws_bedrockagent_knowledge_base.main.id }
output "knowledge_base_arn" { value = aws_bedrockagent_knowledge_base.main.arn }
output "kb_bucket_name" { value = aws_s3_bucket.kb.bucket }
output "opensearch_endpoint" { value = aws_opensearchserverless_collection.main.collection_endpoint }
