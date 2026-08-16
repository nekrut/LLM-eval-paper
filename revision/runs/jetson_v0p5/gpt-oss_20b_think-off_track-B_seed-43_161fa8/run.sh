#!/usr/bin/env bash
set -euo pipefail

THREADS=4

# Ensure results directory exists
mkdir -p results

REF="data/ref/chrM.fa"

# Index reference if needed
if [ ! -f "${REF}.bwt" ]; then
    bwa index "$REF"
fi

samples=(M117-bl M117-ch M117C1-bl M117C1-ch)

check_sample_done() {
    local s=$1
    [[ -f results/${s}.bam && -f results/${s}.bai && -f results/${s}.vcf.gz && -f results/${s}.vcf.gz.tbi ]]
}

all_done=true
for s in "${samples[@]}"; do
    if ! check_sample_done "$s"; then
        all_done=false
        break
    fi
done

if $all_done && [ -f results/collapsed.tsv ]; then
    exit 0
fi

for s in "${samples[@]}"; do
    if check_sample_done "$s"; then
        continue
    fi

    r1="data/raw/${s}_1.fq.gz"
    r2="data/raw/${s}_2.fq.gz"

    bwa mem -t $THREADS "$REF" "$r1" "$r2" | \
        samtools view -Sb - | \
        samtools sort -@ $THREADS -o "results/${s}.bam"

    samtools index "results/${s}.bam"

    lofreq call -f "$REF" -b "results/${s}.bam" -o "results/${s}.vcf"

    bcftools view -O z -o "results/${s}.vcf.gz" "results/${s}.vcf"
    tabix -p vcf "results/${s}.vcf.gz"

    rm -f "results/${s}.vcf"
done

printf "sample\tchrom\tpos\tref\talt\taf\n" > results/collapsed.tsv
for s in "${samples[@]}"; do
    bcftools query -f '%CHROM\t%POS\t%REF\t%ALT[\t%AF]\n' "results/${s}.vcf.gz" | \
        awk -v samp="$s" '{print samp"\t"$0}' >> results/collapsed.tsv
done

exit 0