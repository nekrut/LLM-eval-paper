#!/usr/bin/env bash
set -euo pipefail
THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
mkdir -p results

# Reference indexing — BWA (idempotent check)
if [ ! -f data/ref/chrM.fa.bwt ]; then
    bwa index data/ref/chrM.fa
fi

# Reference indexing — samtools faidx (idempotent check)
if [ ! -f data/ref/chrM.fa.fai ]; then
    samtools faidx data/ref/chrM.fa
fi

# Collapsed TSV header (only write once)
if [ ! -f results/collapsed.tsv ]; then
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > results/collapsed.tsv
fi

for sample in "${SAMPLES[@]}"; do
    bam_file="results/${sample}.bam"
    bai_file="${bam_file}.bai"
    vcf_gz_file="results/${sample}.vcf.gz"
    tbi_file="${vcf_gz_file}.tbi"
    
    # Alignment + sort (idempotent check)
    if [ ! -f "$bam_file" ]; then
        bwa mem -t $THREADS -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" data/ref/chrM.fa data/raw/${sample}_1.fq.gz data/raw/${sample}_2.fq.gz | samtools sort -@ $THREADS -o "$bam_file" -
    fi
    
    # BAM index (idempotent check)
    if [ ! -f "$bai_file" ]; then
        samtools index -@ $THREADS "$bam_file"
    fi
    
    # Variant calling with LoFreq (idempotent check)
    vcf_tmp="results/${sample}.vcf"
    if [ ! -f "$vcf_tmp" ] || [ ! -f "${vcf_tmp}.gz" ]; then
        lofreq call-parallel --pp-threads $THREADS -f data/ref/chrM.fa -o "$vcf_tmp" "$bam_file"
    fi
    
    # VCF compression + tabix index (idempotent check)
    if [ ! -f "$vcf_gz_file" ]; then
        bgzip -c "$vcf_tmp" > "$vcf_gz_file"
    fi
    
    if [ ! -f "$tbi_file" ]; then
        tabix -p vcf "$vcf_gz_file"
    fi
    
    # Append to collapsed TSV (idempotent: check if sample already in file)
    if ! grep -q "^${sample}"$'\t' results/collapsed.tsv; then
        bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "$vcf_gz_file" | awk -v s="$sample" 'BEGIN{OFS="\t"}{print s,$0}' >> results/collapsed.tsv
    fi
done