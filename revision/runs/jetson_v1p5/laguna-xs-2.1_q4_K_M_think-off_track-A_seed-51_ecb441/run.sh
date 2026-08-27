#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

mkdir -p results

# Reference indexing — BWA
if [ ! -f data/ref/chrM.fa.bwt ]; then
    bwa index data/ref/chrM.fa
fi

# Reference indexing — samtools faidx
if [ ! -f data/ref/chrM.fa.fai ]; then
    samtools faidx data/ref/chrM.fa
fi

printf 'sample\tchrom\tpos\tref\talt\taf\n' > results/collapsed.tsv

for sample in "${SAMPLES[@]}"; do
    bam_file="results/${sample}.bam"
    vcf_file="results/${sample}.vcf.gz"
    
    # Check if all outputs exist and are non-empty
    if [ -s "$bam_file" ] && [ -s "${bam_file}.bai" ] && [ -s "$vcf_file" ] && [ -s "${vcf_file}.tbi" ]; then
        continue
    fi
    
    # Per-sample alignment + sort
    bwa mem -t $THREADS -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" data/ref/chrM.fa data/raw/${sample}_1.fq.gz data/raw/${sample}_2.fq.gz | \
        samtools sort -@ $THREADS -o "$bam_file" -
    
    # BAM index
    samtools index -@ $THREADS "$bam_file"
    
    # Variant calling — LoFreq
    lofreq call-parallel --pp-threads $THREADS -f data/ref/chrM.fa -o results/${sample}.vcf "$bam_file"
    
    # VCF compression + tabix index
    bgzip -f -c results/${sample}.vcf > "$vcf_file"
    tabix -p vcf "$vcf_file"
    
    rm -f results/${sample}.vcf
done

# Build collapsed TSV from all samples
for sample in "${SAMPLES[@]}"; do
    bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "results/${sample}.vcf.gz" | \
        awk -v s="$sample" 'BEGIN{OFS="\t"}{print s,$0}' >> results/collapsed.tsv
done