#!/usr/bin/env bash
set -euo pipefail

THREADS=4
sample_list="M117-bl M117-ch M117C1-bl M117C1-ch"

mkdir -p results

# 1. Index chrM once if needed
if [[ ! -f data/ref/chrM.fa.fai ]]; then
    samtools faidx -@ $THREADS data/ref/chrM.fa
fi
if [[ ! -f data/ref/chrM.amb ]] || [[ $(stat -c %Y data/ref/chrM.amb) -lt $(stat -c %Y data/ref/chrM.ffai) ]]; then
    bwa index -a data/ref/chrM.fa

fi

# 2. Per-sample processing
for sample in $sample_list; do
    # alignment & sort BAM
    if [[ ! -f results/${sample}.bam ]] || [[ $(stat -c %Y results/${sample}.bam) -lt $(stat -c %Y data/raw/${sample}_1. fq.gz) ]]; then
        bwa mem -t $THREADS data/raw/${sample}_1. fq.gz data/raw/${sample}_2.f qz | samtools sort -@ $THREADS -o results/${sample}.bam
    fi

    # index BAM
    if [[ ! -f results/${sample}.bam.bai ]] || [[ $(stat -c %Y results/${sample}.bam.bai) -lt $(stat -c %Y results/${sample}.bam) ]]; then
        samtools index -@ $THREADS results/${sample}.bam
    fi

    # variant calling with lofreq call-parallel
    if [[ ! -f results/${sample}.vcf ]] || [[ $(stat -c %Y results/${sample}.vcf) -lt $(stat -c %Y results/${sample}.bam) ]]; then
        lofreq call-parallel --pp-threads 4 --verbose --ref data/ref/chrM.fa --out results/${sample}.vcf --sig --bonf results/${sample}.bam
    fi

    # compress VCF to gz and index with tabix
    if [[ ! -f results/${sample}.vcf.gz ]] || [[ $(stat -c %Y results/${sample}.vcf.gz) -lt $(stat -c %Y results/${sample}.bam) ]]; then
        bgzip -@ $THREADS results/${sample}.vcf > results/${sample}.vcf.gz && rm results/${sample}.vcf
    fi

    if [[ ! -f results/${sample}.vcf.gz.tbi ]] || [[ $(stat -c %Y results/${sample}.vcf.gz.tbi) -lt $(stat -c %Y results/${sample}.vcf.gz) ]]; then
        tabix -p vcf results/${sample}.vcf.gz > results/${sample}.vcf.gz.tbi
    fi

done

# 3. Collapse table
if [[ ! -f results/collapsed.tsv ]] || [[ $(stat -c %Y results/collapsed.tsv) -lt $(for s in $sample_list; do stat -c %Y "results/${s}.vcf.gz"; done | head -n1 ) ]]; then
    tmp=$(mktemp)
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$tmp"
    for s in $sample_list; do
        bcftools query -f '{s}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' results/${s}.vcf.gz >> "$tmp"
    done
    mv "$tmp" results/collapsed.tsv
    rm "$tmp"
fi

exit 0