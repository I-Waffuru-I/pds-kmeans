# Reference applicatie:

```
/data/leuven/303/vsc30380/kmeans_serial_reference \
	--input datasets/mouse_500x2.csv \
	--output output/reference-mouse.csv \
	--repetitions 10 --k 3 --centroidtrace output/ref-centroidtrace-mouse.csv \
	--trace clustertrace.csv --seed 1338
```

resultaat:
`sequential_icc,1,1,datasets/mouse_500x2.csv,1338,3,10,8.11316,0.00158691`

# Onze applicatie:

```
./kmeans \
		--input datasets/mouse_500x2.csv \
		--output output/.csv \
		--centroidtrace output/mouse-centroidrace.csv \
		--repetitions 10   --k 3 \
		--seed 1338
```

resultaat:
`sequential,1,1,datasets/mouse_500x2.csv,1338,3,10,0.090641,0.00230966`

