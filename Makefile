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
	@cd $(SRC)/ingest && \
		if [ -s requirements.txt ] && grep -v '^\s*#' requirements.txt | grep -q .; then \
			pip install --quiet --target build -r requirements.txt; \
			cp handler.py build/; \
			cd build && zip -qr ../../../$(DIST)/ingest.zip . && cd .. && rm -rf build; \
		else \
			zip -q ../../$(DIST)/ingest.zip handler.py; \
		fi
	@echo "Built $(DIST)/ingest.zip"

package-query:
	@mkdir -p $(DIST)
	@rm -f $(DIST)/query.zip
	@cd $(SRC)/query && \
		if [ -s requirements.txt ] && grep -v '^\s*#' requirements.txt | grep -q .; then \
			pip install --quiet --target build -r requirements.txt; \
			cp handler.py build/; \
			cd build && zip -qr ../../../$(DIST)/query.zip . && cd .. && rm -rf build; \
		else \
			zip -q ../../$(DIST)/query.zip handler.py; \
		fi
	@echo "Built $(DIST)/query.zip"
