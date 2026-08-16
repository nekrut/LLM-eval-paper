#!/usr/bin/env bash
set -euo pipefail

THREADS=4
samples=(M117-bl M117-ch M117C1-bl M117C1-ch)
mkdir -p results

# Reference indexing (once)
if [ ! -f data/ref/chrM.fa.fai ]; then
    samtools faidx data/ref/chrM.fa
fi

if [ ! -f data/ref/chrM.fa.bwt ]; then
    bwa index data/ref/chrM.fa
fi

for sample in "${samples[@]}"; do
    # Skip if final output exists
    if [ -f results/${sample}.vcf.gz.tbi ]; then
        continue
    fi

    # Alignment and sorting
    bwa mem -t $THREADS \
        -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
        data/ref/chrM.fa \
        <(zcat data/raw/${sample}_1.fq.gz) \
        <(zcat data/raw/${sample}_2.fq.gz) | \
    samtools sort -@ $THREADS -o results/${sample}.bam

    # Index BAM
    samtools index -@ $THREADS results/${sample}.bam

    # Variant calling with lofreq call-parallel
    lofreq call-parallel --pp-threads $THREADS \
        -r data/ref/chrM.fa \
        results/${sample}.bam > results/${sample}.vcf

    # Compress and index VCF
    bgzip -c results/${sample}.vcf > results/${sample}.vcf.gz
    tabix -p vcf results/${sample}.vcf.gz
    rm results/${sample}.vcf
done

# Collapsed TSV step
need_collapse=0
if [ ! -f results/collapsed.tsv ]; then
    need_collapse=1
else
    for s in "${samples[@]}"; do
        if [[ "$(stat -c %Y results/${s}.vcf.gz.tbi)" -gt "$(stat -c %Y results/collapsed.tsv)" ]]; then
            need_collapse=1
            break
        fi
    done
fi

if [ "$need_collapse" -eq 1 ]; then
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > results/collapsed.tsv
    for sample in "${samples[@]}"; do
        bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" \
            results/${sample}.vcf.gz >> results/collapsed.tsv
    done
fi

exit 0