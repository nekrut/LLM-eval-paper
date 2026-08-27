#!/usr/bin/env bash
set -euo pipefail

THREADS=4
samples=(M117-bl M117-ch M117C1-bl M117C1-ch)

mkdir -p results

# Reference indexing
if [ ! -s data/ref/chrM.fa.fai ]; then
    samtools faidx data/ref/chrM.fa
fi
if [ ! -s data/ref/chrM.fa.amb ]; then
    bwa index data/ref/chrM.fa
fi

for s in "${samples[@]}"; do
    if [ -s "results/${s}.vcf.gz.tbi" ]; then
        continue
    fi

    bwa mem -t "$THREADS" \
        -R "@RG\\tID:${s}\\tSM:${s}\\tLB:${s}\\tPL:ILLUMINA" \
        data/raw/"${s}"_1.fq.gz data/raw/"${s}"_2.fq.gz |
        samtools sort -@ "$THREADS" -o "results/${s}.bam"

    samtools index -@ "$THREADS" "results/${s}.bam"

    lofreq call-parallel --pp-threads "$THREADS" \
        -f data/ref/chrM.fa -o "results/${s}.vcf" "results/${s}.bam"

    bgzip -c "results/${s}.vcf" > "results/${s}.vcf.gz"
    tabix -p vcf "results/${s}.vcf.gz"
    rm -f "results/${s}.vcf"
done

rebuild=false
if [ ! -s results/collapsed.tsv ]; then
    rebuild=true
else
    for f in results/*.vcf.gz; do
        if [ "$f" -nt results/collapsed.tsv ]; then
            rebuild=true
            break
        fi
    done
fi

if $rebuild; then
    tmp=$(mktemp)
    for s in "${samples[@]}"; do
        bcftools query -f '{sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "results/${s}.vcf.gz" | \
            sed "s/{sample}/$s/" >> "$tmp"
    done
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > results/collapsed.tsv
    cat "$tmp" >> results/collapsed.tsv
    rm -f "$tmp"
fi

exit 0