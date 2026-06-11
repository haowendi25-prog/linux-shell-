.PHONY: install clean

install:
	chmod +x diagmaster/diagmaster.sh diagmaster/modules/*.sh diagmaster/lib/*.sh
	@echo "DiagMaster installed successfully. Run: ./diagmaster/diagmaster.sh"

clean:
	rm -f diagmaster/data/*.tmp diagmaster/data/**/*.tmp diagmaster/data/history/*.log
	rm -f diagmaster/logs/*.log
	rm -f diagmaster/reports/*.md diagmaster/reports/*.log diagmaster/reports/*.json
	@echo "Runtime artifacts cleaned."
