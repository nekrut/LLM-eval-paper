#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES="M117-bl M117-ch M117C1-bl M117C1-ch"
REF="data/ref/chrM.fa"

mkdir -p results

if [ ! -f "${REF}.bwt" ]; then
    samtools faidx "$REF"
    bwa index "$REF"
fi

for s in $SAMPLES; do
    if [ ! -f "results/${s}.vcf.gz.tbi" ] || \
       [ "data/raw/${s}_1.fq.gz" -nt "results/${s}.vcf.gz.tbi" ] || \
       [ "data/raw/${s}_2.fq.gz" -nt "results/${s}.vcf.gz.tbi" ]; then
        
        bwa mem -t "$THREADS" -R "@RG\tID:${s}\tSM:${s}\tLB:${s}\tPL:ILLUMINA" \
            "$REF" "data/raw/${s}_1.fq.gz" "data/raw/${s}_2.fq.gz" | \
            samtools sort -@ "$THREADS" -o "results/${s}.bam"

        samtools index -@ "$THREADS" "results/${s}.bam"

        lofreq call-parallel --pp-threads "$THREADS" -f "$REF" -o "results/${s}.vcf" "results/${s}.bam"

        bgzip -c "results/${s}.vcf" > "results/${s}.vcf.gz"
        tabix -p vcf "results/${s}.vcf.gz"
        rm "results/${s}.vcf"
    fi
done

NEEDS_COLLAPSE=false
for s in $SAMPLES; do
    if [ ! -f "results/${s}.vcf.gz" ] || [ "results/${s}.vcf.gz" -nt "results/collapsed.tsv" ]; then
        NEEDS_COLLAPSE=true
        break
    fi
done

if [ "$NEEDS_COLLAPSE" = true ]; then
    printf "sample\tchrom\tpos\tref\talt\taf\n" > results/collapsed.tsv
    for s in $SAMPLES; do
        bcftools query -f "${s}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "results/${s}.vcf.gz" >> results/collapsed.tsv
    done
fi

exit 0