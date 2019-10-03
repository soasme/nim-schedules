doc:
	nim doc --project --threads:on src/scheduler.nim
	mv src/htmldocs/* docs
