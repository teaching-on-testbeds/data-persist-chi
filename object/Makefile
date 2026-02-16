all: \
	index.md \
	0_intro.ipynb \
	1_create_server.ipynb \
	2_local_baseline.ipynb \
	3_create_bucket.ipynb \
	4_rclone_mount.ipynb \
	5_rclone_baseline.ipynb \
	6_remote_one_sample.ipynb \
	7_webdataset.ipynb \
	8_litdata.ipynb \
	9_delete.ipynb

clean: 
	rm -f index.md \
	0_intro.ipynb \
	1_create_server.ipynb \
	2_local_baseline.ipynb \
	3_create_bucket.ipynb \
	4_rclone_mount.ipynb \
	5_rclone_baseline.ipynb \
	6_remote_one_sample.ipynb \
	7_webdataset.ipynb \
	8_litdata.ipynb \
	9_delete.ipynb

index.md: snippets/*.md 
	cat snippets/intro.md \
		snippets/create_server.md \
		snippets/local_baseline.md \
		snippets/create_bucket.md \
		snippets/rclone_mount.md \
		snippets/rclone_baseline.md \
		snippets/remote_one_sample.md \
		snippets/webdataset.md \
		snippets/litdata.md \
		snippets/delete.md \
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


2_local_baseline.ipynb: snippets/local_baseline.md
	pandoc --resource-path=../ --embed-resources --standalone --wrap=none \
				-i snippets/frontmatter_python.md snippets/local_baseline.md \
				-o 2_local_baseline.ipynb  
	sed -i 's/attachment://g' 2_local_baseline.ipynb


3_create_bucket.ipynb: snippets/create_bucket.md
	pandoc --resource-path=../ --embed-resources --standalone --wrap=none \
				-i snippets/frontmatter_python.md snippets/create_bucket.md \
				-o 3_create_bucket.ipynb  
	sed -i 's/attachment://g' 3_create_bucket.ipynb


4_rclone_mount.ipynb: snippets/rclone_mount.md
	pandoc --resource-path=../ --embed-resources --standalone --wrap=none \
				-i snippets/frontmatter_python.md snippets/rclone_mount.md \
				-o 4_rclone_mount.ipynb  
	sed -i 's/attachment://g' 4_rclone_mount.ipynb


5_rclone_baseline.ipynb: snippets/rclone_baseline.md
	pandoc --resource-path=../ --embed-resources --standalone --wrap=none \
				-i snippets/frontmatter_python.md snippets/rclone_baseline.md \
				-o 5_rclone_baseline.ipynb  
	sed -i 's/attachment://g' 5_rclone_baseline.ipynb


6_remote_one_sample.ipynb: snippets/remote_one_sample.md
	pandoc --resource-path=../ --embed-resources --standalone --wrap=none \
				-i snippets/frontmatter_python.md snippets/remote_one_sample.md \
				-o 6_remote_one_sample.ipynb  
	sed -i 's/attachment://g' 6_remote_one_sample.ipynb


7_webdataset.ipynb: snippets/webdataset.md
	pandoc --resource-path=../ --embed-resources --standalone --wrap=none \
				-i snippets/frontmatter_python.md snippets/webdataset.md \
				-o 7_webdataset.ipynb  
	sed -i 's/attachment://g' 7_webdataset.ipynb


8_litdata.ipynb: snippets/litdata.md
	pandoc --resource-path=../ --embed-resources --standalone --wrap=none \
				-i snippets/frontmatter_python.md snippets/litdata.md \
				-o 8_litdata.ipynb  
	sed -i 's/attachment://g' 8_litdata.ipynb

9_delete.ipynb: snippets/delete.md
	pandoc --resource-path=../ --embed-resources --standalone --wrap=none \
				-i snippets/frontmatter_python.md snippets/delete.md \
				-o 9_delete.ipynb  
	sed -i 's/attachment://g' 9_delete.ipynb
