#!/usr/bin/env bash
set -euo pipefail

THREADS=4
samples="M117-bl M117-ch M117C1-bl M117C1-ch"

mkdir -p results

# Reference indexing
if [[ ! -f data/ref/chrM.fa.fai ]]; then
    samtools faidx data/ref/chrM.fa
fi
if [[ ! -f data/ref/chrM.fa.bwt ]]; then
    bwa index data/ref/chrM.fa
fi

for sample in $samples; do
    tbi="results/${sample}.vcf.gz.tbi"
    if [[ -f $tbi ]]; then
        continue
    fi

    # alignment
    bwa mem -t 4 -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" data/ref/chrM.fa data/raw/${sample}_1.fq.gz data/raw/${sample}_2.fq.gz |
        samtools sort -@ 4 -o results/${sample}.bam

    # indexing
    samtools index -@ 4 results/${sample}.bam

    # variant calling
    lofreq call-parallel --pp-threads 4 -f data/ref/chrM.fa -o results/${sample}.vcf results/${sample}.bam

    # compress VCF
    bgzip -c results/${sample}.vcf > results/${sample}.vcf.gz

    # index compressed VCF
    tabix -p vcf results/${sample}.vcf.gz

    # remove intermediate uncompressed VCF
    rm -f results/${sample}.vcf
done

# collapse step
collapse_needed=0
if [[ -f results/collapsed.tsv ]]; then
    tsv_mtime=$(stat -c %Y results/collapsed.tsv)
    for s in $samples; do
        vcf_gz="results/${s}.vcf.gz"
        if [[ -f $vcf_gz && $(stat -c %Y $vcf_gz) -gt $tsv_mtime ]]; then
            collapse_needed=1
            break
        fi
    done
else
    collapse_needed=1
fi

if ((collapse_needed)); then
    {
        printf 'sample\tchrom\tpos\tref\talt\taf\n'
        for s in $samples; do
            bcftools query -f '{sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' results/${s}.vcf.gz
        done
    } > results/collapsed.tsv
fi

exit 0