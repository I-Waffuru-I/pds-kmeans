# Naïve measurements

## Gewoon hashmap vervangen door een vector met voorgedefiniërde grootte

```makefile
run: build
 ./$(BUILD) --input $(DATA)/100000x5.csv \
  --output $(OUTPUT)/output.csv \
  --repetitions 20   --k 10 \
  --seed 1337
```

before:
39.4266 sec

Per iteratie  kan het wel oplopen van 1-8seconden. Raar dat er zo een groot verschil op zit. Is er geen manier om dit iets te versnellen? Misschien cache writes?

after:
38.497 sec

## Hoe zouden we het nog kunnen versnellen?

- Octal trees?
  - hebben we  dan nog wel dezelfde trace?

- Wat als ik ze naar een matrix omzet en zo naar een evenwichtssituatie probeer te heleiden met markov?
 	- We kunnen dan op zich de matrix mult verbeteren door matmul van vorig labo te gebruiken voor beter cache gebruik.
