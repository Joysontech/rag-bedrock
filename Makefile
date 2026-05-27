.PHONY: init fmt validate plan apply destroy nuke costs pause resume snapshot-list package package-ingest package-query

TF_DIR := terraform
DIST   := dist
SRC    := src

SNAPSHOT_ID := rag-bedrock-$(shell date +%Y%m%d-%H%M%S)

init:
	cd $(TF_DIR) && terraform init

fmt:
	cd $(TF_DIR) && terraform fmt -recursive

validate:
	cd $(TF_DIR) && terraform validate

plan:
	cd $(TF_DIR) && terraform plan -out=tfplan

apply:
	cd $(TF_DIR) && terraform apply tfplan

destroy:
	cd $(TF_DIR) && terraform destroy -auto-approve

nuke: destroy
	@aws resourcegroupstaggingapi get-resources \
		--tag-filters Key=Project,Values=rag-bedrock \
		--query 'ResourceTagMappingList[].ResourceARN' \
		--output table

costs:
	@if [[ "$$OSTYPE" == "darwin"* ]]; then \
		START=$$(date -u -v-7d +%Y-%m-%d); \
	else \
		START=$$(date -u -d '7 days ago' +%Y-%m-%d); \
	fi; \
	END=$$(date -u +%Y-%m-%d); \
	aws ce get-cost-and-usage \
		--time-period Start=$$START,End=$$END \
		--granularity DAILY \
		--metrics UnblendedCost \
		--filter '{"Tags":{"Key":"Project","Values":["rag-bedrock"]}}' \
		--group-by Type=DIMENSION,Key=SERVICE \
		--output table

pause:
	@echo "Waiting for cluster to be available..."
	@aws rds wait db-cluster-available --db-cluster-identifier rag-bedrock-cluster
	@echo "Creating snapshot: $(SNAPSHOT_ID)"
	@aws rds create-db-cluster-snapshot \
		--db-cluster-identifier rag-bedrock-cluster \
		--db-cluster-snapshot-identifier $(SNAPSHOT_ID) \
		--query 'DBClusterSnapshot.DBClusterSnapshotIdentifier' --output text
	@echo "Waiting for snapshot to complete..."
	@aws rds wait db-cluster-snapshot-available \
		--db-cluster-snapshot-identifier $(SNAPSHOT_ID)
	@echo "Snapshot ready. Safe to destroy."
	@$(MAKE) destroy

snapshot-list:
	@aws rds describe-db-cluster-snapshots \
		--db-cluster-identifier rag-bedrock-cluster \
		--snapshot-type manual \
		--query 'DBClusterSnapshots[].{ID:DBClusterSnapshotIdentifier,Status:Status,Created:SnapshotCreateTime}' \
		--output table

resume:
	@echo "Restore via console: RDS -> Snapshots -> select latest -> Restore"
	@echo "Use cluster identifier: rag-bedrock-cluster"
	@$(MAKE) snapshot-list

package: package-ingest package-query

package-ingest:
	@mkdir -p $(DIST)
	@rm -f $(DIST)/ingest.zip
	@rm -rf $(SRC)/ingest/build
	@mkdir -p $(SRC)/ingest/build
	@if [ -s $(SRC)/ingest/requirements.txt ] && grep -v '^\s*#' $(SRC)/ingest/requirements.txt | grep -q .; then \
		pip install --quiet \
			--platform manylinux2014_x86_64 \
			--target $(SRC)/ingest/build \
			--implementation cp \
			--python-version 3.12 \
			--only-binary=:all: \
			-r $(SRC)/ingest/requirements.txt; \
	fi
	@cp $(SRC)/ingest/handler.py $(SRC)/ingest/build/
	@if [ -d $(SRC)/shared ]; then cp -r $(SRC)/shared $(SRC)/ingest/build/; fi
	@cd $(SRC)/ingest/build && zip -qr ../../../$(DIST)/ingest.zip .
	@rm -rf $(SRC)/ingest/build
	@echo "Built $(DIST)/ingest.zip ($$(du -h $(DIST)/ingest.zip | cut -f1))"

package-query:
	@mkdir -p $(DIST)
	@rm -f $(DIST)/query.zip
	@rm -rf $(SRC)/query/build
	@mkdir -p $(SRC)/query/build
	@if [ -s $(SRC)/query/requirements.txt ] && grep -v '^\s*#' $(SRC)/query/requirements.txt | grep -q .; then \
		pip install --quiet \
			--platform manylinux2014_x86_64 \
			--target $(SRC)/query/build \
			--implementation cp \
			--python-version 3.12 \
			--only-binary=:all: \
			-r $(SRC)/query/requirements.txt; \
	fi
	@cp $(SRC)/query/handler.py $(SRC)/query/build/
	@if [ -d $(SRC)/shared ]; then cp -r $(SRC)/shared $(SRC)/query/build/; fi
	@cd $(SRC)/query/build && zip -qr ../../../$(DIST)/query.zip .
	@rm -rf $(SRC)/query/build
	@echo "Built $(DIST)/query.zip ($$(du -h $(DIST)/query.zip | cut -f1))"
