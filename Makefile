all: \
	index.md \
	0_intro.ipynb

clean: 
	rm -f index.md 0_intro.ipynb


index.md: snippets/*.md block/snippets/*.md object/snippets/*.md
	cat snippets/intro.md \
		block/snippets/intro.md \
		block/snippets/create_server.md \
		block/snippets/block.md \
		block/snippets/cinder.md \
		object/snippets/intro.md \
		object/snippets/create_server.md \
		object/snippets/local_baseline.md \
		object/snippets/create_bucket.md \
		object/snippets/rclone_mount.md \
		object/snippets/rclone_baseline.md \
		object/snippets/remote_one_sample.md \
		object/snippets/webdataset.md \
		object/snippets/litdata.md \
		object/snippets/delete.md \
		snippets/footer.md \
		> index.tmp.md
	grep -v '^:::' index.tmp.md > index.md
	rm index.tmp.md
0_intro.ipynb: snippets/intro.md
	pandoc --resource-path=../ --embed-resources --standalone --wrap=none \
                -i snippets/frontmatter_python.md snippets/intro.md \
                -o 0_intro.ipynb  
	sed -i 's/attachment://g' 0_intro.ipynb
