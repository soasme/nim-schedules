doc:
	nim doc --project --threads:on src/schedules.nim
	rm -rf docs/_build && mv src/htmldocs/ docs/_build
	cd docs/_build && git init && git add -A && git commit -m'build pages' && git push -f git@github.com:soasme/nim-schedules.git master:gh-pages
