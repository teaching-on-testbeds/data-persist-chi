all: \
	index.md \
	0_intro.ipynb \
	1_create_server.ipynb \
	2_block.ipynb \
	3_cinder.ipynb

clean: 
	rm -f index.md \
	0_intro.ipynb \
	1_create_server.ipynb \
	2_block.ipynb \
	3_cinder.ipynb

index.md: snippets/*.md 
	cat snippets/intro.md \
		snippets/create_server.md \
		snippets/block.md \
		snippets/cinder.md \
		snippets/footer.md \
		> index.tmp.md
	grep -v '^:::' index.tmp.md > index.md
	rm index.tmp.md

0_intro.ipynb: snippets/intro.md
	pandoc --resource-path=../ --embed-resources --standalone --wrap=none \
                -i snippets/frontmatter_python.md snippets/intro.md \
                -o 0_intro.ipynb  
	sed -i 's/attachment://g' 0_intro.ipynb


1_create_server.ipynb: snippets/create_server.md
	pandoc --resource-path=../ --embed-resources --standalone --wrap=none \
                -i snippets/frontmatter_python.md snippets/create_server.md \
                -o 1_create_server.ipynb  
	sed -i 's/attachment://g' 1_create_server.ipynb

2_block.ipynb: snippets/block.md	
	pandoc --resource-path=../ --embed-resources --standalone --wrap=none \
				-i snippets/frontmatter_python.md snippets/block.md \
				-o 2_block.ipynb  
	sed -i 's/attachment://g' 2_block.ipynb

3_cinder.ipynb: snippets/cinder.md
	pandoc --resource-path=../ --embed-resources --standalone --wrap=none \
				-i snippets/frontmatter_python.md snippets/cinder.md \
				-o 3_cinder.ipynb  
	sed -i 's/attachment://g' 3_cinder.ipynb
