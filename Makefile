doc:
	rm -rf docs/_build
	nim doc --project --out:docs/_build --threads:on --index:on src/schedules.nim
	cd docs/_build && git init && git add -A && git commit -m'build pages' && git push -f https://soasme:$${GH_PAGES_ACCESS_TOKEN}@github.com/soasme/nim-schedules.git master:gh-pages
