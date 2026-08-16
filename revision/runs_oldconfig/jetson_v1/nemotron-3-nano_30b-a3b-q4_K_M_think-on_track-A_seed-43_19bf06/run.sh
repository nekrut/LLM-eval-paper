#!/usr/bin/env bash
set -euo pipefail

THREADS=4
samples="M117-bl M117-ch M117C1-bl M117C1-ch"

mkdir -p results

# Exit early if all final artifacts already exist
all_done=1
for s in $samples; do
    if [ ! -e results/${s}.vcf.gz.tbi ]; then
        all_done=0; break
    fi
done
if [ $all_done -eq 1 ] && [ -e results/collapsed.tsv ]; then
    exit 0
fi

ref=data/ref/chrM.fa

# Index reference (once)
if [ ! -e data/ref/chrM.fa.fai ]; then
    samtools faidx "$ref"
fi
if [ ! -e data/ref/chrM.fa.bwt ]; then
    bwa index "$ref"
fi

for sample in $samples; do
    # Skip if final TBI already exists
    if [ -e results/${sample}.vcf.gz.tbi ]; then
        continue
    fi

    fastq1=data/raw/${sample}_1.fq.gz
    fastq2=data/raw/${sample}_2.fq.gz

    # Align and sort (skip if BAM already exists)
    if [ ! -e results/${sample}.bam ]; then
        bwa mem -t $THREADS \
          -R "@RG\\tID:${sample}\\tSM:${sample}\\tLB:${sample}\\tPL:ILLUMINA" \
          "$ref" "$fastq1" "$fastq2" |
          samtools sort -@ $THREADS -o results/${sample}.bam
    fi

    # Index BAM (skip if index exists)
    if [ ! -e results/${sample}.bam.bai ]; then
        samtools index -@ $THREADS results/${sample}.bam
    fi

    # Variant calling with lofreq
    lofreq call-parallel --pp-threads 4 -f "$ref" -o results/${sample}.vcf results/${sample}.bam

    # Compress VCF and index
    bgzip -c results/${sample}.vcf > results/${sample}.vcf.gz
    tabix -p vcf results/${sample}.vcf.gz
    rm results/${sample}.vcf
done

# Build collapsed.tsv (only if not already built)
if [ ! -s results/collapsed.tsv ]; then
    echo -e "sample\tchrom\tpos\tref\talt\taf" > results/collapsed.tsv
fi
for sample in $samples; do
    bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' results/${sample}.vcf.gz |
        awk -v s="${sample}" '{print s"\t"$0}' >> results/collapsed.tsv
done

exit 0